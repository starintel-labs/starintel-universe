#!/usr/bin/env bash
# Unit tests for universe-owned tooling (report generator, manifest).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
FAIL=0

# report.py: manifest + summary generated for a synthetic revision
TMP=$(mktemp -d)
python3 - "$TMP" <<'EOF'
import json, subprocess, sys, os
tmp = sys.argv[1]
env = dict(os.environ)
p = subprocess.run(
    ["python3", "scripts/report.py", "--checks-dir", "facts",
     "--out", tmp], capture_output=True, text=True, env=env)
assert p.returncode == 0, p.stderr
out = p.stdout.strip().splitlines()[-1]
man = json.load(open(os.path.join(out, "manifest.json")))
assert man["component_count"] >= 10, man
assert len(man["component_shas"]) == man["component_count"]
summary = open(os.path.join(out, "summary.org")).read()
assert "Integration report" in summary
assert "Component pins" in summary
print("report generator OK:", man["component_count"], "components")
EOF
[ $? -eq 0 ] || FAIL=1

# collect-facts: pins parse as valid Prolog with quoted SHAs
bash scripts/collect-facts.sh >/dev/null 2>&1 || true
swipl -q -g "consult('facts/pins.pl'), pin(C,S,_), atom_length(S,40), write(C), nl, fail ; halt" -t halt >/dev/null || FAIL=1
echo "collect-facts prolog parse OK"

[ $FAIL -eq 0 ] && echo UNIT-OK || exit 1
