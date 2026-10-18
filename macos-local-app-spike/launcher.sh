#!/bin/sh

set -eu

app_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
resources="$app_root/Contents/Resources"
default_data_root="$(CDPATH= cd -- "$app_root/.." && pwd)/data"
data_root=${DIGITALTWIN_APP_DATA_ROOT:-$default_data_root}
short_data_root="$(CDPATH= cd -- "$app_root/../.." && pwd)/dt"

case "$data_root" in
  /*) ;;
  *) printf '%s\n' "DIGITALTWIN_APP_DATA_ROOT must be absolute" >&2; exit 64 ;;
esac

postgres_port=${DIGITALTWIN_APP_POSTGRES_PORT:-15432}
web_port=${DIGITALTWIN_APP_WEB_PORT:-13000}
hermes_port=${DIGITALTWIN_APP_HERMES_PORT:-18642}
adapter_port=${DIGITALTWIN_APP_ADAPTER_PORT:-13087}
opencode_port=${DIGITALTWIN_APP_OPENCODE_PORT:-13086}
api_token=

for port in "$postgres_port" "$web_port" "$hermes_port" "$adapter_port" "$opencode_port"; do
  case "$port" in
    *[!0-9]*|'') printf '%s\n' "DigitalTwin app ports must be numeric" >&2; exit 64 ;;
  esac
done

run_root="$data_root/run"
log_root="$data_root/logs"
postgres_data="$data_root/postgres"
hermes_home="$data_root/hermes/profile"
pid_root="$run_root/pids"
commander_workspace="$data_root/commander-workspace"
opencode_root="$data_root/opencode"
opencode_home="$opencode_root/home"
opencode_tmp="$opencode_root/tmp"
opencode_executable="$resources/OpenCode.app/Contents/MacOS/OpenCode Dev"

mkdir -p "$run_root" "$log_root" "$pid_root" "$data_root/heartbeats" "$data_root/home" "$data_root/tmp" "$commander_workspace"
umask 077

if test "$data_root" = "$default_data_root"; then
  if ! test -e "$short_data_root"; then
    ln -s "$data_root" "$short_data_root"
  fi
  if test -d "$short_data_root"; then
    hermes_home="$short_data_root/h"
  fi
fi

export HOME="$data_root/home"
export TMPDIR="$data_root/tmp"
export PATH="$resources/postgres/bin:$resources/ruby/bin:/usr/bin:/bin"
unset GEM_HOME GEM_PATH RUBYOPT BUNDLE_BIN_PATH BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_USER_CONFIG
export BUNDLE_IGNORE_CONFIG=1
export RUBYLIB="$resources/ruby/lib/ruby/4.0.0:$resources/ruby/lib/ruby/4.0.0/arm64-darwin27"

pid_file() { printf '%s/%s.pid\n' "$pid_root" "$1"; }

alive() {
  test -f "$(pid_file "$1")" || return 1
  read -r pid < "$(pid_file "$1")"
  kill -0 "$pid" 2>/dev/null
}

wait_for() {
  label=$1
  shift
  attempts=0
  until "$@" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if test "$attempts" -ge 60; then
      printf '%s\n' "Timed out waiting for $label" >&2
      return 1
    fi
    sleep 1
  done
}

start_postgres() {
  if ! test -f "$postgres_data/PG_VERSION"; then
    "$resources/postgres/bin/initdb" --auth=trust --username=digitaltwin --pgdata="$postgres_data" >> "$log_root/postgres.log" 2>&1
  fi
  if ! "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin --dbname=digitaltwin_spike >/dev/null 2>&1; then
    "$resources/postgres/bin/pg_ctl" --pgdata="$postgres_data" --log="$log_root/postgres.log" --options="-h 127.0.0.1 -p $postgres_port" start >> "$log_root/postgres.log" 2>&1
  fi
  wait_for "PostgreSQL" "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin --dbname=digitaltwin_spike
  if ! "$resources/postgres/bin/psql" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin --dbname=postgres --tuples-only --no-align --command="SELECT 1 FROM pg_database WHERE datname = 'digitaltwin_spike'" | grep -qx 1; then
    "$resources/postgres/bin/createdb" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin digitaltwin_spike
  fi
}

start_kirei() {
  kirei="$resources/kirei"
  ruby="$resources/ruby/bin/ruby"
  bundled_bin="$kirei/vendor/bundle/ruby/4.0.0/bin"
  test -x "$bundled_bin/rake" || { printf '%s\n' "Kirei rake executable is missing from the bundled gems" >&2; exit 78; }
  test -x "$bundled_bin/falcon" || { printf '%s\n' "Kirei Falcon executable is missing from the bundled gems" >&2; exit 78; }
  export DATABASE_URL="postgres://digitaltwin@127.0.0.1:$postgres_port/digitaltwin_spike"
  export PORT="$web_port"
  export HEARTBEAT_DIR="$data_root/heartbeats"
  export BUNDLE_PATH="$kirei/vendor/bundle"
  export BUNDLE_GEMFILE="$kirei/Gemfile"
  (
    cd "$kirei"
    "$ruby" -rbundler/setup "$bundled_bin/rake" db:migrate
  ) >> "$log_root/kirei-migrate.log" 2>&1
  (
    cd "$kirei"
    exec "$ruby" -rbundler/setup "$bundled_bin/falcon" serve --bind "http://0.0.0.0:$web_port" --count 1 --config "$kirei/config.ru"
  ) >> "$log_root/kirei-web.log" 2>&1 &
  echo $! > "$(pid_file kirei-web)"
  (
    cd "$kirei"
    exec "$ruby" -rbundler/setup bin/worker
  ) >> "$log_root/kirei-worker.log" 2>&1 &
  echo $! > "$(pid_file kirei-worker)"
  wait_for "Kirei web" "$resources/ruby/bin/ruby" "$kirei/bin/health" web
  wait_for "Kirei worker" "$resources/ruby/bin/ruby" "$kirei/bin/health" worker
}

ensure_hermes_token() {
  test -n "$api_token" && return
  api_token=$("$resources/ruby/bin/ruby" -rsecurerandom -e 'print SecureRandom.hex(32)')
  test -n "$api_token" || { printf '%s\n' "Unable to generate the local Hermes control token" >&2; exit 78; }
}

start_hermes() {
  ensure_hermes_token
  mkdir -p "$hermes_home"
  if ! test -f "$hermes_home/config.yaml"; then
    cp "$resources/hermes/profile/config.yaml.example" "$hermes_home/config.yaml"
    cp "$resources/hermes/profile/SOUL.md" "$hermes_home/SOUL.md"
    cp "$resources/hermes/profile/AGENTS.md" "$hermes_home/AGENTS.md"
  fi
  export HERMES_HOME="$hermes_home"
  export HERMES_INSTALL_ROOT="$resources/hermes/source"
  export HERMES_RUNTIME_DIR="$resources/hermes/runtime"
  export HERMES_GATEWAY_LOCK_DIR="$run_root/hermes-locks"
  export XDG_CACHE_HOME="$data_root/hermes/cache"
  export XDG_CONFIG_HOME="$data_root/hermes/config"
  export XDG_DATA_HOME="$data_root/hermes/data"
  export XDG_RUNTIME_DIR="$run_root/hermes"
  export XDG_STATE_HOME="$data_root/hermes/state"
  export API_SERVER_HOST=127.0.0.1
  export API_SERVER_PORT="$hermes_port"
  mkdir -p "$HERMES_GATEWAY_LOCK_DIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
  (
    export API_SERVER_KEY="$api_token"
    exec "$resources/bin/hermes" gateway
  ) >> "$log_root/hermes.log" 2>&1 &
  echo $! > "$(pid_file hermes)"
  wait_for "Hermes API listener" hermes_rejects_anonymous_request
}

hermes_rejects_anonymous_request() {
  status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:$hermes_port/v1/models" || true)
  test "$status" = 401
}

start_adapter() {
  ensure_hermes_token
  export DIGITALTWIN_HERMES_STATE_FILE="$data_root/hermes/adapter-state.json"
  export DIGITALTWIN_HERMES_ADAPTER_PORT="$adapter_port"
  export DIGITALTWIN_HERMES_API_URL="http://127.0.0.1:$hermes_port"
  export DIGITALTWIN_HERMES_API_TOKEN="$api_token"
  export DIGITALTWIN_HERMES_ADAPTER_TOKEN="$api_token"
  export DIGITALTWIN_HERMES_ALLOWED_PROVIDER=anthropic
  "$resources/bin/hermes-adapter" >> "$log_root/hermes-adapter.log" 2>&1 &
  echo $! > "$(pid_file hermes-adapter)"
  wait_for "Hermes adapter" curl --silent --fail --output /dev/null --max-time 2 "http://127.0.0.1:$adapter_port/health"
}

prepare_commander_workspace() {
  agent_directory="$commander_workspace/.opencode/agents"
  agent_file="$agent_directory/commander.md"
  baseline="$resources/commander/commander-agent-baseline.md"

  test -f "$baseline" || { printf '%s\n' "Bundled Commander agent baseline is missing" >&2; exit 78; }
  mkdir -p "$agent_directory"
  if ! test -e "$agent_file"; then
    cp "$baseline" "$agent_file"
  fi
}

launch_opencode() {
  test -x "$opencode_executable" || { printf '%s\n' "Bundled OpenCode executable is missing" >&2; exit 78; }
  prepare_commander_workspace

  # Keep Electron, its sidecar, and its shell-environment probe inside this app's
  # writable root. The app owns this state and must not adopt a user's desktop
  # service, provider configuration, or regular development profile.
  mkdir -p "$opencode_home" "$opencode_tmp"
  export HOME="$opencode_home"
  export TMPDIR="$opencode_tmp"
  export SHELL=/bin/sh
  export DIGITALTWIN_OPENCODE_DATA_ROOT="$opencode_root"
  export DIGITALTWIN_COMMANDER_WORKSPACE="$commander_workspace"
  export DIGITALTWIN_COMMANDER_AGENT=commander
  export DIGITALTWIN_HERMES_ADAPTER_URL="http://127.0.0.1:$adapter_port"
  export DIGITALTWIN_OPENCODE_ISOLATED_SERVER=1
  export DIGITALTWIN_OPENCODE_ISOLATED_SERVER_PORT="$opencode_port"
  export OPENCODE_DESKTOP_SERVER_CHANNEL=local
  export OPENCODE_DESKTOP_DISABLE_PROTOCOL_REGISTRATION=1
  unset API_SERVER_KEY BUNDLE_GEMFILE BUNDLE_IGNORE_CONFIG BUNDLE_PATH DIGITALTWIN_HERMES_API_TOKEN GEM_HOME GEM_PATH RUBYLIB RUBYOPT ZDOTDIR

  "$opencode_executable" >> "$log_root/opencode.log" 2>&1 &
  echo $! > "$(pid_file opencode)"
  if wait "$!"; then
    result_code=0
  else
    result_code=$?
  fi
  rm -f "$(pid_file opencode)"
  return "$result_code"
}

stop_named() {
  name=$1
  if alive "$name"; then
    read -r pid < "$(pid_file "$name")"
    kill -TERM "$pid" 2>/dev/null || true
    attempts=0
    while kill -0 "$pid" 2>/dev/null && test "$attempts" -lt 15; do
      attempts=$((attempts + 1))
      sleep 1
    done
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$(pid_file "$name")"
}

stop_opencode_sidecar() {
  for registration in "$opencode_root/desktop/opencode/service.json" "$opencode_root/desktop/opencode/service-local.json"; do
    test -f "$registration" || continue
    sidecar_pid=$("$resources/ruby/bin/ruby" -rjson -e 'value = JSON.parse(File.read(ARGV.fetch(0))); pid = value["pid"]; print(pid) if pid.is_a?(Integer) && pid.positive?' "$registration" 2>/dev/null || true)
    case "$sidecar_pid" in
      *[!0-9]*|'') continue ;;
    esac
    sidecar_command=$(ps -p "$sidecar_pid" -o command= 2>/dev/null || true)
    case "$sidecar_command" in
      "$opencode_root"/desktop/cli/*)
        kill -TERM "$sidecar_pid" 2>/dev/null || true
        attempts=0
        while kill -0 "$sidecar_pid" 2>/dev/null && test "$attempts" -lt 15; do
          attempts=$((attempts + 1))
          sleep 1
        done
        kill -0 "$sidecar_pid" 2>/dev/null && kill -KILL "$sidecar_pid" 2>/dev/null || true
        rm -f "$registration"
        ;;
    esac
  done
}

start() {
  ensure_hermes_token
  start_postgres
  start_kirei
  start_hermes
  start_adapter
}

stop() {
  stop_opencode_sidecar
  stop_named hermes-adapter
  stop_named hermes
  stop_named kirei-worker
  stop_named kirei-web
  if test -f "$postgres_data/PG_VERSION"; then
    "$resources/postgres/bin/pg_ctl" --pgdata="$postgres_data" stop --mode=fast >> "$log_root/postgres.log" 2>&1 || true
  fi
}

status() {
  "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin --dbname=digitaltwin_spike
  curl --silent --fail --output /dev/null --max-time 2 "http://127.0.0.1:$web_port/readyz"
  test -f "$data_root/heartbeats/digitaltwin-worker.heartbeat"
  curl --silent --fail --output /dev/null --max-time 2 "http://127.0.0.1:$adapter_port/health"
}

verify() {
  start
  status
  stop
  start
  status
  stop
}

launch() {
  start
  trap 'stop' 0
  trap 'stop; exit 0' 1 2 15
  launch_opencode
}

case "${1:-launch}" in
  launch) launch ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  verify) verify ;;
  *) printf '%s\n' "Usage: DigitalTwin [launch|start|stop|status|verify]" >&2; exit 64 ;;
esac
