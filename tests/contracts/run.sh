#!/usr/bin/env bash
# Contract tests: the interfaces the universe depends on stay stable.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
FAIL=0
check() { # name, command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS: $name"; else echo "FAIL: $name"; FAIL=1; fi
}

# 1. star-cl conformance adapter answers its contract commands
if [ -f components/star-cl/bin/starintel-conformance.lisp ] && command -v sbcl >/dev/null; then
  check "star-cl adapter: version" bash -c \
    "echo '{\"command\":\"version\"}' | sbcl --script components/star-cl/bin/starintel-conformance.lisp"
else
  echo "SKIP: star-cl adapter (sbcl or file missing)"
fi

# 2. control plane CLI contract: exit codes
bash scripts/collect-facts.sh >/dev/null 2>&1 || true
swipl -q .prolog/cli.pl pins >/dev/null
rc_pins=$?
check "cli pins exit 0" test "$rc_pins" -eq 0
swipl -q .prolog/cli.pl deployment_allowed candidate staging >/dev/null 2>&1 && rc_skip=0 || rc_skip=$?
check "cli deployment skip denied (exit 1)" test "$rc_skip" -eq 1

# 3. starintel-server target contract (documented constants)
grep -q "+target-max-delay-seconds* 31536000" \
  components/starintel-server/source/target-dispatch.lisp 2>/dev/null || \
  grep -q "31536000" components/starintel-server/source/target-dispatch.lisp
check "target delay upper bound constant"

# 4. quasar control plane protocol version
grep -q '"quasar.control.v1"' components/quasar/control-plane/src/protocol.lisp \
  2>/dev/null || grep -q "quasar.control.v1" \
  components/quasar/control-plane/src/protocol.lisp
check "quasar protocol version string"

[ $FAIL -eq 0 ] && echo CONTRACTS-OK || exit 1
