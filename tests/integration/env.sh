#!/usr/bin/env bash
# Shared environment for the universe full-stack test harness.
# Services bind to loopback only; no secrets beyond throwaway CI credentials.
set -euo pipefail

export STARINTEL_UNIVERSE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export STARINTEL_TEST_NET="starintel-universe-test"
export STARINTEL_TEST_DIR="${STARINTEL_TEST_DIR:-$(mktemp -d /tmp/starintel-universe-test.XXXXXX)}"
mkdir -p "$STARINTEL_TEST_DIR"

# Throwaway credentials for the disposable test stack. These are NOT secrets.
export COUCHDB_USER="${COUCHDB_USER:-admin}"
export COUCHDB_PASSWORD="${COUCHDB_PASSWORD:-starintel-test}"
export COUCHDB_HOST="${COUCHDB_HOST:-127.0.0.1}"
export COUCHDB_PORT="${COUCHDB_PORT:-5984}"
export COUCHDB_DATABASE="${COUCHDB_DATABASE:-starintel}"
export RABBITMQ_ADDRESS="${RABBITMQ_ADDRESS:-127.0.0.1}"
export RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"
export RABBITMQ_USER="${RABBITMQ_USER:-guest}"
export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-guest}"
export HTTP_API_LISTEN_ADDRESS="${HTTP_API_LISTEN_ADDRESS:-127.0.0.1}"
export HTTP_API_PORT="${HTTP_API_PORT:-15000}"
export STAR_SERVER_URL="http://127.0.0.1:${HTTP_API_PORT}"
export STAR_SERVER_BIN="${STAR_SERVER_BIN:-${STAR_SERVER_BIN_OVERRIDE:-/tmp/opencode/star-server/bin/star-server}}"
export STAR_SERVER_PID_FILE="$STARINTEL_TEST_DIR/star-server.pid"
export STAR_SERVER_LOG="$STARINTEL_TEST_DIR/star-server.log"
export STARINTEL_TEST_ACTOR_CONFIG="$STARINTEL_TEST_DIR/actor-config"
export STARINTEL_TEST_INIT="$STARINTEL_UNIVERSE_ROOT/tests/actors/lib/test-init.lisp"

log() { printf '[harness] %s\n' "$*" >&2; }
