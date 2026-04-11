#!/usr/bin/env bats
# Feature 006 T044 — chrome_click CLI dispatcher surface bats suite.
#
# Smoke-tests the chrome_click dispatch path. Full behavioral tests
# require mocked Chrome — see tests/integration/ for those.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  # shellcheck disable=SC1090
  source "$LIB"
}

@test "click: chrome_click function is defined" {
  type chrome_click > /dev/null 2>&1
}

@test "click: missing args returns non-zero" {
  run chrome_click
  [ "$status" -ne 0 ]
}

@test "click: chrome_click function references the safety gauntlet" {
  # Source-level assertion: chrome_click MUST call safety check helpers
  awk '/^chrome_click\(\)/,/^}$/' "$LIB" | grep -q "_chrome_check_url_blocklist" \
    || awk '/^chrome_click\(\)/,/^}$/' "$LIB" | grep -q "_chrome_safety_check_js"
}

@test "click: chrome_click references rate limiter" {
  awk '/^chrome_click\(\)/,/^}$/' "$LIB" | grep -q "_chrome_rate_check\|rate_check"
}

@test "click: chrome_click references audit log" {
  awk '/^chrome_click\(\)/,/^}$/' "$LIB" | grep -q "_chrome_audit_append\|audit_append"
}
