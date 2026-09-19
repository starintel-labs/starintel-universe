% Tooling facts.
tool(test_stack, 'tests/integration/up.sh: couch 25984, rabbit 25672, valkey 26379, star-server 15000; down.sh tears down').
tool(proof_chain, 'tests/e2e/vanta_plan.pl: prolog-rlm plan_run with trusted tool starintel_target; quasar legs need quasar-server binary + session token from http://<host>/ (CLOG boot page), WS origin must be in the default allowlist (e.g. http://127.0.0.1:8080)').
tool(quasar_envelopes, 'quasar.control.v1: document.create payload IS the document (no nesting); metadata.workspace selects the workspace').
tool(universe_manager, 'actors/universe-manager/bin/universe-manager {inspect,discover,facts,propose,apply,gate,promote}; swipl cli.pl exit 0/1/2').
