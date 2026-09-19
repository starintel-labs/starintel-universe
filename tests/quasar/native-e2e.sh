#!/usr/bin/env bash
# Upstream quasar e2e (their Playwright suites, run at the pinned revision).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== quasar full-stack e2e"
( cd components/quasar \
  && npm ci \
  && npx playwright install --with-deps chromium \
  && npm run test:e2e )

echo "== quasar-ui native e2e"
( cd components/quasar-ui \
  && npm ci \
  && npx playwright install --with-deps chromium \
  && npm run test:e2e )
