#!/bin/sh
set -eu

# One-shot local setup operates only on explicitly mounted named volumes.
# Mattermost's distroless image cannot seed writable configuration itself.
test "$(id -u)" = 0
test -f /seed/phase0.json
for path in chat-config chat-data chat-logs; do
  test -d "/volumes/$path"
  chown 2000:2000 "/volumes/$path"
done
if [ ! -f /volumes/chat-config/config.json ]; then
  cp /seed/phase0.json /volumes/chat-config/config.json
fi
chown 2000:2000 /volumes/chat-config/config.json
for path in runtime-home runtime-workspace herdr-socket; do
  test -d "/volumes/$path"
  chown 10001:10001 "/volumes/$path"
done
chmod 700 /volumes/herdr-socket
