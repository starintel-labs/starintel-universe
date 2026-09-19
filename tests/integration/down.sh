#!/usr/bin/env bash
# Tear down the disposable full-stack environment.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [ -f "$STAR_SERVER_PID_FILE" ]; then
  pid="$(cat "$STAR_SERVER_PID_FILE")"
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 10); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -9 "$pid" 2>/dev/null || true
fi
docker rm -f starintel-test-couchdb starintel-test-rabbit starintel-test-valkey >/dev/null 2>&1 || true
docker network rm "$STARINTEL_TEST_NET" >/dev/null 2>&1 || true
log "stack DOWN"
