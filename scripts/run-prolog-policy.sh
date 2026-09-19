#!/usr/bin/env bash
# Run the full Prolog control-plane suite (policies + structural invariants).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec swipl -q \
  -g "consult('.prolog/universe'), consult('.prolog/policy_suite'), run_tests, halt(0)" \
  -t "halt(2)"
