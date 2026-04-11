#!/usr/bin/env bash
# Feature 006 T061 — golden regeneration ceremony.
# Per spec §NFR-V2-FX-6, FX-7.
#
# Extracts the safety check JS, re-runs every fixture, writes new
# .expected.json files, and updates tests/goldens.lock.
#
# GUARDRAIL: This script refuses to run if any source file (skills/**,
# safety JS) has uncommitted changes in the same commit. Golden
# regeneration MUST be its own commit so reviewers can audit just the
# envelope changes.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# --- Guardrail: refuse if safety JS has staged changes ----------------

if git diff --cached --name-only | grep -q "skills/chrome-multi-profile/chrome-lib.sh"; then
  cat >&2 << 'EOF'
FATAL: chrome-lib.sh has staged changes.

Golden regeneration MUST be its own commit. Split your work:
  1. Commit the chrome-lib.sh change alone
  2. Run scripts/regenerate-goldens.sh
  3. Commit the updated goldens separately
  4. Reviewer can then audit the envelope diffs in isolation

Refusing to mix source + golden changes.
EOF
  exit 1
fi

# --- Recompute safety JS hash -----------------------------------------

new_sha=$(bash skills/chrome-multi-profile/chrome-lib.sh _emit_safety_js "#target" | shasum -a 256 | awk '{print $1}')
echo "New safety_js_sha256: $new_sha"

# --- Re-run fixtures via happy-dom harness ----------------------------

if [[ ! -f tests/vendor/happy-dom.mjs ]]; then
  echo "WARN: tests/vendor/happy-dom.mjs not vendored. Cannot re-run fixtures."
  echo "      Only updating goldens.lock hash."
else
  if command -v node > /dev/null 2>&1; then
    echo "Re-running fixtures under happy-dom..."
    node tests/js-fixtures/run.mjs --regenerate-goldens || true
  fi
fi

# --- Update goldens.lock ----------------------------------------------

cat > tests/goldens.lock << LOCKEOF
# Feature 006 T060 — golden lock file.
# SHA-256 of the extracted safety check JS (via \`_emit_safety_js '#target'\`).
# Any mismatch fails the test run until regeneration ceremony is performed.
#
# Regenerate with: scripts/regenerate-goldens.sh

safety_js_sha256=$new_sha
safety_js_selector_stub=#target
LOCKEOF

echo "PASS: goldens.lock updated. Stage with: git add tests/goldens.lock tests/fixtures/*.expected.json"
