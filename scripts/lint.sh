#!/usr/bin/env bash
# lint.sh — contributor lint + smoke tests for claude-mac-chrome
#
# Runs:
#   1. shfmt format check (2-space indent, switch indent, space-redirect)
#   2. shellcheck at style severity
#   3. Basic smoke test of the library (if Chrome is available)
#
# Requirements:
#   - bash 4.0+
#   - shfmt (https://github.com/mvdan/sh) — brew install shfmt, or nix
#   - shellcheck — brew install shellcheck, or nix
#   - jq (https://jqlang.github.io/jq/) — brew install jq, or nix

set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
readonly LINT_SELF="$REPO_ROOT/scripts/lint.sh"

fail_count=0
skip_count=0

step() {
  printf '\n\033[1;36m▶ %s\033[0m\n' "$*"
}

ok() {
  printf '  \033[1;32m✓\033[0m %s\n' "$*"
}

skip() {
  printf '  \033[1;33m-\033[0m %s\n' "$*"
  skip_count=$((skip_count + 1))
}

err() {
  printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2
  fail_count=$((fail_count + 1))
}

# Check if a tool is available either in PATH or via `nix run nixpkgs#<pkg>`.
# Returns 0 if available, 1 if not. Prints nothing.
have_tool() {
  local name="$1"
  command -v "$name" > /dev/null 2>&1 && return 0
  if command -v nix > /dev/null 2>&1; then
    nix --extra-experimental-features 'nix-command flakes' run \
      "nixpkgs#$name" -- --version > /dev/null 2>&1 && return 0
  fi
  return 1
}

# Invoke a tool either from PATH or via `nix run nixpkgs#<pkg>`. Forwards all args.
run_tool() {
  local name="$1"
  shift
  if command -v "$name" > /dev/null 2>&1; then
    "$name" "$@"
    return
  fi
  nix --extra-experimental-features 'nix-command flakes' run \
    "nixpkgs#$name" -- "$@"
}

# ---- shfmt ----
step "shfmt format check"
if have_tool shfmt; then
  if run_tool shfmt -i 2 -ci -sr -d "$LIB" "$LINT_SELF" > /dev/null 2>&1; then
    ok "shfmt: no formatting diff"
  else
    err "shfmt: formatting differences found — run 'shfmt -i 2 -ci -sr -w <file>' to fix"
    run_tool shfmt -i 2 -ci -sr -d "$LIB" "$LINT_SELF" || true
  fi
else
  skip "shfmt: not found (install via 'brew install shfmt' or 'nix-shell -p shfmt')"
fi

# ---- shellcheck ----
step "shellcheck at style severity"
if have_tool shellcheck; then
  if run_tool shellcheck --shell=bash --severity=style "$LIB" "$LINT_SELF"; then
    ok "shellcheck: clean"
  else
    err "shellcheck: warnings found"
  fi
else
  skip "shellcheck: not found (install via 'brew install shellcheck' or 'nix-shell -p shellcheck')"
fi

# ---- zero-Python check (v0.4.0) ----
step "zero-Python heredoc check"
python_count=$(grep -c 'python3 <<\|python3 -c' "$LIB" || true)
if [[ "$python_count" -eq 0 ]]; then
  ok "zero Python heredocs in chrome-lib.sh"
else
  err "found $python_count Python heredoc(s) — v0.4.0 requires full elimination"
fi

# ---- v0.8.0 forbidden pattern check ----
step "v0.8.0 forbidden-pattern check (eval, form.submit)"
if grep -nE '\beval\b' "$LIB" | grep -v '^[[:space:]]*#' > /dev/null 2>&1; then
  err "eval found in chrome-lib.sh — forbidden"
else
  ok "no eval found"
fi
if grep -nE 'form\.submit\(\)' "$LIB" > /dev/null 2>&1; then
  err "form.submit() found in chrome-lib.sh — forbidden by NFR-SR-4"
else
  ok "no form.submit() found"
fi

# ---- v0.8.0 safety helper presence check ----
step "v0.8.0 safety helper presence"
required_helpers=(
  "_chrome_check_url_blocklist"
  "_chrome_load_trigger_lexicon"
  "_chrome_rate_check"
  "_chrome_audit_append"
  "_chrome_tty_confirm"
  "_chrome_prompt_injection_scan"
  "_chrome_check_domain_allowlist"
  "_chrome_safety_check_js"
  "chrome_click"
  "chrome_query"
  "chrome_wait_for"
)
missing_helpers=0
for helper in "${required_helpers[@]}"; do
  if ! grep -q "^${helper}()" "$LIB"; then
    err "missing required v0.8.0 helper: $helper"
    missing_helpers=$((missing_helpers + 1))
  fi
done
if ((missing_helpers == 0)); then
  ok "all v0.8.0 safety helpers present"
fi

# ---- Happy-DOM fidelity lint (feature 006 T014) ----
step "happy-dom fidelity matrix coverage"
fidelity_doc="$REPO_ROOT/docs/HAPPY-DOM-FIDELITY.md"
if [[ -f "$fidelity_doc" ]]; then
  # Extract DOM API calls inside _chrome_safety_check_js body
  js_apis=$(awk '/^_chrome_safety_check_js\(\)/,/^}/' "$LIB" |
    grep -oE '(getBoundingClientRect|getComputedStyle|elementFromPoint|showModal|querySelector|querySelectorAll|shadowRoot|closest|getAttribute|textContent|innerText|offsetParent|offsetWidth|offsetHeight|readyState|visibilityState|MutationObserver|normalize)' |
    sort -u)
  missing_doc=0
  for api in $js_apis; do
    if ! grep -q "\`.*$api.*\`" "$fidelity_doc"; then
      err "DOM API '$api' used in safety JS but not in HAPPY-DOM-FIDELITY.md"
      missing_doc=$((missing_doc + 1))
    fi
  done
  if ((missing_doc == 0)); then
    ok "all DOM APIs documented in fidelity matrix"
  fi
else
  skip "HAPPY-DOM-FIDELITY.md not found"
fi

# ---- Fixture determinism lint (feature 006 T063) ----
step "fixture determinism (no Math.random / Date.now / crypto.randomUUID)"
if [[ -d "$REPO_ROOT/tests/fixtures" ]]; then
  banned_pattern='Math\.random|Date\.now|crypto\.randomUUID|performance\.now'
  if grep -rE "$banned_pattern" "$REPO_ROOT/tests/fixtures" > /dev/null 2>&1; then
    err "non-deterministic API found in fixtures — breaks golden reproducibility"
    grep -rnE "$banned_pattern" "$REPO_ROOT/tests/fixtures" || true
  else
    ok "fixtures are deterministic"
  fi
fi

# ---- smoke test ----
step "smoke test (requires Chrome running with Apple Events JS permission)"
if [[ "$OSTYPE" != "darwin"* ]]; then
  ok "skipped (not macOS)"
elif ! command -v osascript > /dev/null 2>&1; then
  ok "skipped (osascript not available)"
else
  if "$LIB" catalog | jq . > /dev/null 2>&1; then
    ok "catalog: valid JSON"
  else
    err "catalog: failed to parse Local State"
  fi
  if "$LIB" fingerprint | jq . > /dev/null 2>&1; then
    ok "fingerprint: valid JSON output"
  else
    err "fingerprint: failed"
  fi
  wid=$("$LIB" cached 2> /dev/null | jq -r '
    (.by_dir // {} | to_entries | .[0].value // empty)
  ' 2> /dev/null || true)
  if [[ -n "${wid:-}" ]]; then
    tid=$("$LIB" tab_for_url "$wid" "://" 2> /dev/null || true)
    if [[ -n "${tid:-}" ]]; then
      if "$LIB" js "$wid" "$tid" "1 + 1" > /dev/null 2>&1; then
        ok "js round-trip: OK"
      else
        err "js round-trip: failed"
      fi
    else
      ok "tab_for_url: no tab matched (fine for a clean profile)"
    fi
  else
    ok "no matched window (Chrome may not be running or no email-bearing tab open)"
  fi
fi

# ---- test suite wiring (feature 006 T066) ----
step "tests/run.sh (bats + js-fixtures + mutation)"
if [[ -x "$REPO_ROOT/tests/run.sh" ]]; then
  if "$REPO_ROOT/tests/run.sh"; then
    ok "tests/run.sh: all stages passed"
  else
    err "tests/run.sh: one or more stages failed"
  fi
else
  skip "tests/run.sh not found or not executable"
fi

# ---- summary ----
printf '\n'
if ((fail_count == 0)); then
  if ((skip_count > 0)); then
    printf '\033[1;32mAll checks passed\033[0m (%d skipped)\n' "$skip_count"
  else
    printf '\033[1;32mAll checks passed.\033[0m\n'
  fi
  exit 0
else
  printf '\033[1;31m%d check(s) failed.\033[0m\n' "$fail_count"
  exit 1
fi
