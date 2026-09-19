#!/usr/bin/env bash
# Actor-to-actor communication slice of the matrix (requires up.sh stack).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=$(ls -dt /tmp/starintel-universe-test.* | head -1)
STAR_SERVER_URL=http://127.0.0.1:15000 \
COUCH_URL=http://127.0.0.1:25984 \
STARINTEL_TEST_ACTOR_CONFIG=$D/actor-config \
  python3 tests/integration/test_actor_matrix.py \
    ActorMatrix.test_01_every_actor_routes \
    ActorMatrix.test_10_echo_roundtrip \
    ActorMatrix.test_11_serialization_preserves_payload \
    ActorMatrix.test_20_transform \
    ActorMatrix.test_21_actor_to_actor_chain \
    ActorMatrix.test_30_streaming
echo A2A-OK
