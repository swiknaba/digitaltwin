#!/bin/sh

set -eu

app_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
resources="$app_root/Contents/Resources"
default_data_root="$(CDPATH= cd -- "$app_root/.." && pwd)/data"
data_root=${DIGITALTWIN_APP_DATA_ROOT:-$default_data_root}

case "$data_root" in
  /*) ;;
  *) printf '%s\n' "DIGITALTWIN_APP_DATA_ROOT must be absolute" >&2; exit 64 ;;
esac

postgres_port=${DIGITALTWIN_APP_POSTGRES_PORT:-15432}
web_port=${DIGITALTWIN_APP_WEB_PORT:-13000}
hermes_port=${DIGITALTWIN_APP_HERMES_PORT:-18642}
adapter_port=${DIGITALTWIN_APP_ADAPTER_PORT:-13087}
token_file=${DIGITALTWIN_HERMES_API_TOKEN_FILE:-}

for port in "$postgres_port" "$web_port" "$hermes_port" "$adapter_port"; do
  case "$port" in
    *[!0-9]*|'') printf '%s\n' "DigitalTwin app ports must be numeric" >&2; exit 64 ;;
  esac
done

run_root="$data_root/run"
log_root="$data_root/logs"
postgres_data="$data_root/postgres"
hermes_home="$data_root/hermes/profile"
pid_root="$run_root/pids"

mkdir -p "$run_root" "$log_root" "$pid_root" "$data_root/heartbeats" "$data_root/home" "$data_root/tmp"
umask 077

export HOME="$data_root/home"
export TMPDIR="$data_root/tmp"
export PATH="$resources/postgres/bin:$resources/ruby/bin:/usr/bin:/bin"

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
  until "$@"; do
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
  if ! "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin >/dev/null 2>&1; then
    "$resources/postgres/bin/pg_ctl" --pgdata="$postgres_data" --log="$log_root/postgres.log" --options="-h 127.0.0.1 -p $postgres_port" start >> "$log_root/postgres.log" 2>&1
  fi
  wait_for "PostgreSQL" "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin
  if ! "$resources/postgres/bin/psql" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin --dbname=postgres --tuples-only --no-align --command="SELECT 1 FROM pg_database WHERE datname = 'digitaltwin_spike'" | grep -qx 1; then
    "$resources/postgres/bin/createdb" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin digitaltwin_spike
  fi
}

start_kirei() {
  kirei="$resources/kirei"
  export DATABASE_URL="postgres://digitaltwin@127.0.0.1:$postgres_port/digitaltwin_spike"
  export PORT="$web_port"
  export HEARTBEAT_DIR="$data_root/heartbeats"
  export BUNDLE_PATH="$kirei/vendor/bundle"
  export BUNDLE_GEMFILE="$kirei/Gemfile"
  (
    cd "$kirei"
    "$resources/ruby/bin/bundle" exec rake db:migrate
  ) >> "$log_root/kirei-migrate.log" 2>&1
  (
    cd "$kirei"
    exec "$resources/ruby/bin/ruby" bin/web
  ) >> "$log_root/kirei-web.log" 2>&1 &
  echo $! > "$(pid_file kirei-web)"
  (
    cd "$kirei"
    exec "$resources/ruby/bin/ruby" bin/worker
  ) >> "$log_root/kirei-worker.log" 2>&1 &
  echo $! > "$(pid_file kirei-worker)"
  wait_for "Kirei web" "$resources/ruby/bin/ruby" "$kirei/bin/health" web
  wait_for "Kirei worker" "$resources/ruby/bin/ruby" "$kirei/bin/health" worker
}

start_hermes() {
  test -n "$token_file" && test -s "$token_file" || { printf '%s\n' "DIGITALTWIN_HERMES_API_TOKEN_FILE must name an existing token file" >&2; exit 78; }
  mkdir -p "$hermes_home"
  if ! test -f "$hermes_home/config.yaml"; then
    cp "$resources/hermes/profile/config.yaml.example" "$hermes_home/config.yaml"
    cp "$resources/hermes/profile/SOUL.md" "$hermes_home/SOUL.md"
    cp "$resources/hermes/profile/AGENTS.md" "$hermes_home/AGENTS.md"
  fi
  api_token=$(< "$token_file")
  export HERMES_HOME="$hermes_home"
  export HERMES_INSTALL_ROOT="$resources/hermes/source"
  export HERMES_RUNTIME_DIR="$resources/hermes/runtime"
  export HERMES_GATEWAY_LOCK_DIR="$run_root/hermes-locks"
  export XDG_CACHE_HOME="$data_root/hermes/cache"
  export XDG_CONFIG_HOME="$data_root/hermes/config"
  export XDG_DATA_HOME="$data_root/hermes/data"
  export XDG_RUNTIME_DIR="$run_root/hermes"
  export XDG_STATE_HOME="$data_root/hermes/state"
  export API_SERVER_KEY="$api_token"
  export API_SERVER_HOST=127.0.0.1
  export API_SERVER_PORT="$hermes_port"
  mkdir -p "$HERMES_GATEWAY_LOCK_DIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
  "$resources/bin/hermes" gateway >> "$log_root/hermes.log" 2>&1 &
  echo $! > "$(pid_file hermes)"
  wait_for "Hermes API listener" hermes_rejects_anonymous_request
}

hermes_rejects_anonymous_request() {
  status=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:$hermes_port/v1/models" || true)
  test "$status" = 401
}

start_adapter() {
  export DIGITALTWIN_HERMES_STATE_FILE="$data_root/hermes/adapter-state.json"
  export DIGITALTWIN_HERMES_ADAPTER_PORT="$adapter_port"
  export DIGITALTWIN_HERMES_API_URL="http://127.0.0.1:$hermes_port"
  export DIGITALTWIN_HERMES_API_TOKEN="$(< "$token_file")"
  export DIGITALTWIN_HERMES_ADAPTER_TOKEN="$DIGITALTWIN_HERMES_API_TOKEN"
  export DIGITALTWIN_HERMES_ALLOWED_PROVIDER=anthropic
  "$resources/bin/hermes-adapter" >> "$log_root/hermes-adapter.log" 2>&1 &
  echo $! > "$(pid_file hermes-adapter)"
  wait_for "Hermes adapter" curl --silent --fail --output /dev/null --max-time 2 "http://127.0.0.1:$adapter_port/health"
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

start() {
  start_postgres
  start_kirei
  start_hermes
  start_adapter
}

stop() {
  stop_named hermes-adapter
  stop_named hermes
  stop_named kirei-worker
  stop_named kirei-web
  if test -f "$postgres_data/PG_VERSION"; then
    "$resources/postgres/bin/pg_ctl" --pgdata="$postgres_data" stop --mode=fast >> "$log_root/postgres.log" 2>&1 || true
  fi
}

status() {
  "$resources/postgres/bin/pg_isready" --host=127.0.0.1 --port="$postgres_port" --username=digitaltwin
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

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  verify) verify ;;
  *) printf '%s\n' "Usage: DigitalTwin [start|stop|status|verify]" >&2; exit 64 ;;
esac
