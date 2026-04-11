#!/usr/bin/env bash
# Feature 006 T017 — test runner entrypoint.
# Invoked by scripts/lint.sh as the final step.
#
# Order:
#   1. bats (shell unit tests) — FAST, mandatory
#   2. node tests/js-fixtures/run.mjs — medium, skipped if vendor bundle missing
#   3. Stryker mutation pass (if available) — slow, optional gating
#
# Exit non-zero on first failure. No partial runs.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail_all=0

# --- Step 1: bats ------------------------------------------------------

if ! command -v bats > /dev/null 2>&1; then
  echo "SKIP  bats not installed (brew install bats-core)"
else
  echo "--- bats shell tests ---"
  # Prepend mockbin so osascript calls hit the stub
  export PATH="$REPO_ROOT/tests/mockbin:$PATH"
  if bats tests/bats/*.bats; then
    echo "PASS  bats"
  else
    echo "FAIL  bats"
    fail_all=$((fail_all + 1))
  fi
fi

# --- Step 2: JS fixture runner -----------------------------------------

if [[ ! -f tests/vendor/happy-dom.mjs ]]; then
  echo "SKIP  js-fixtures (tests/vendor/happy-dom.mjs not vendored yet)"
elif ! command -v node > /dev/null 2>&1; then
  echo "SKIP  js-fixtures (node not installed)"
else
  echo "--- js-fixtures (happy-dom harness) ---"
  if node tests/js-fixtures/run.mjs; then
    echo "PASS  js-fixtures"
  else
    echo "FAIL  js-fixtures"
    fail_all=$((fail_all + 1))
  fi
fi

# --- Step 3: Stryker (optional) ----------------------------------------

if [[ -f tests/stryker.conf.mjs ]] && [[ -d node_modules/.bin ]] && [[ -x node_modules/.bin/stryker ]]; then
  echo "--- Stryker mutation testing ---"
  if npx stryker run tests/stryker.conf.mjs > /tmp/stryker.log 2>&1; then
    echo "PASS  Stryker (see /tmp/stryker.log)"
  else
    echo "FAIL  Stryker (see /tmp/stryker.log)"
    fail_all=$((fail_all + 1))
  fi
else
  echo "SKIP  Stryker (install with 'npm install --no-save @stryker-mutator/core' in repo root)"
fi

if [[ $fail_all -gt 0 ]]; then
  echo ""
  echo "FAIL  $fail_all test stage(s) failed"
  exit 1
fi

echo ""
echo "PASS  all test stages"
exit 0
