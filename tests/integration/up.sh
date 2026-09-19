#!/usr/bin/env bash
# Boot the disposable full-stack StarIntel environment for integration tests.
#
#   CouchDB  :127.0.0.1:25984  (admin/starintel-test — throwaway)
#   RabbitMQ :127.0.0.1:25672  (guest/guest, loopback-only container)
#   Valkey   :127.0.0.1:26379
#   star-server: 127.0.0.1:15000 with the deterministic test actors loaded
set -euo pipefail
source "$(dirname "$0")/env.sh"

# Port-forwarded host ports (kept OFF the service defaults so a developer
# machine running real services is never disturbed).
export COUCHDB_PORT=25984
export RABBITMQ_PORT=25672
export VALKEY_PORT=26379

command -v docker >/dev/null || { log "docker is required"; exit 2; }

cleanup_existing() {
  docker rm -f starintel-test-couchdb starintel-test-rabbit starintel-test-valkey >/dev/null 2>&1 || true
}
cleanup_existing

docker network create "$STARINTEL_TEST_NET" >/dev/null 2>&1 || true

log "starting couchdb"
docker run -d --rm --name starintel-test-couchdb \
  --network "$STARINTEL_TEST_NET" \
  -e COUCHDB_USER="$COUCHDB_USER" -e COUCHDB_PASSWORD="$COUCHDB_PASSWORD" \
  -p 127.0.0.1:25984:5984 \
  couchdb:3 >/dev/null

log "starting rabbitmq"
docker run -d --rm --name starintel-test-rabbit \
  --network "$STARINTEL_TEST_NET" \
  -e RABBITMQ_DEFAULT_USER=guest -e RABBITMQ_DEFAULT_PASS=guest \
  -p 127.0.0.1:25672:5672 \
  rabbitmq:4-management >/dev/null

log "starting valkey"
docker run -d --rm --name starintel-test-valkey \
  --network "$STARINTEL_TEST_NET" \
  -p 127.0.0.1:26379:6379 \
  valkey/valkey:8 >/dev/null

wait_http() {
  local url="$1" name="$2" tries=90
  for _ in $(seq 1 $tries); do
    if curl -sf -m 3 -o /dev/null "$url"; then log "$name ready"; return 0; fi
    sleep 1
  done
  log "$name NEVER became ready ($url)"; exit 1
}
wait_tcp() {
  local host="$1" port="$2" name="$3" tries=90
  for _ in $(seq 1 $tries); do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then exec 3>&- 3<&-; log "$name ready"; return 0; fi
    sleep 1
  done
  log "$name NEVER became ready ($host:$port)"; exit 1
}

wait_http "http://127.0.0.1:25984/" "couchdb"
wait_tcp 127.0.0.1 25672 "rabbitmq"
wait_tcp 127.0.0.1 26379 "valkey"

[ -x "$STAR_SERVER_BIN" ] || { log "star-server binary missing at $STAR_SERVER_BIN"; exit 2; }

log "starting star-server with test actors"
: > "$STARINTEL_TEST_ACTOR_CONFIG"
printf 'mode=default\n' > "$STARINTEL_TEST_ACTOR_CONFIG"

(
  cd "$STARINTEL_TEST_DIR"
  env COUCHDB_PORT=25984 RABBITMQ_PORT=25672 \
      HTTP_API_LISTEN_ADDRESS=127.0.0.1 HTTP_API_PORT=15000 \
      STAR_AUTH_MODE=disabled STAR_AUTH_DEV_BYPASS=true \
      STARINTEL_TEST_ACTOR_CONFIG="$STARINTEL_TEST_ACTOR_CONFIG" \
      STARINTEL_TEST_ACTORS="$STARINTEL_UNIVERSE_ROOT/tests/actors/lib/starintel-test-actors.lisp" \
    nohup "$STAR_SERVER_BIN" start -i "$STARINTEL_TEST_INIT" \
    < /dev/null > "$STAR_SERVER_LOG" 2>&1 &
  echo $! > "$STAR_SERVER_PID_FILE"
)

wait_http "$STAR_SERVER_URL/health" "star-server"
log "stack UP: $STAR_SERVER_URL (logs: $STAR_SERVER_LOG)"
