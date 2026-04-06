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
#   - python3 (stdlib only, no pip install needed)

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

# ---- smoke test ----
step "smoke test (requires Chrome running with Apple Events JS permission)"
if [[ "$OSTYPE" != "darwin"* ]]; then
  ok "skipped (not macOS)"
elif ! command -v osascript > /dev/null 2>&1; then
  ok "skipped (osascript not available)"
else
  if "$LIB" catalog | python3 -m json.tool > /dev/null 2>&1; then
    ok "catalog: valid JSON"
  else
    err "catalog: failed to parse Local State"
  fi
  if "$LIB" fingerprint | python3 -m json.tool > /dev/null 2>&1; then
    ok "fingerprint: valid JSON output"
  else
    err "fingerprint: failed"
  fi
  wid=$("$LIB" cached 2> /dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    vs = list(d.get("by_dir", {}).values())
    print(vs[0] if vs else "")
except Exception:
    pass
' || true)
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
