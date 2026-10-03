#!/bin/sh
# Downloads public pinned source and test dependencies; never provider credentials.
set -eu
component=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/digitaltwin-push-upstream.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
git clone --quiet --depth 1 --branch v6.6.0 https://github.com/mattermost/mattermost-push-proxy.git "$scratch/source"
test "$(git -C "$scratch/source" rev-parse HEAD)" = 20f2a046fef76a7ab1c121cd01bc2b06206979be
cp "$component/tests/retry_upstream_test.go" "$scratch/source/server/digitaltwin_retry_test.go"
docker run --rm -v "$scratch/source:/source" -w /source golang:1.26 go test -count=1 ./... -v
