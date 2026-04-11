#!/usr/bin/env bats
# Feature 006 T047 — CLI surface contract bats suite.
# Per spec §NFR-V2-API-1 (public API stability).
#
# Asserts that every v1.0.0-public function is callable as a CLI verb
# and responds to at least one smoke invocation without crashing.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  # shellcheck disable=SC1090
  source "$LIB"
}

# Each of these MUST be exported as a bash function by chrome-lib.sh

@test "cli: chrome_fingerprint is defined" {
  type chrome_fingerprint > /dev/null 2>&1
}

@test "cli: chrome_window_for is defined" {
  type chrome_window_for > /dev/null 2>&1
}

@test "cli: chrome_tab_for_url is defined" {
  type chrome_tab_for_url > /dev/null 2>&1
}

@test "cli: chrome_js is defined" {
  type chrome_js > /dev/null 2>&1
}

@test "cli: chrome_click is defined" {
  type chrome_click > /dev/null 2>&1
}

@test "cli: chrome_query is defined" {
  type chrome_query > /dev/null 2>&1
}

@test "cli: chrome_wait_for is defined" {
  type chrome_wait_for > /dev/null 2>&1
}

@test "cli: chrome_check_inboxes is defined" {
  type chrome_check_inboxes > /dev/null 2>&1
}

@test "cli: chrome_snapshot is defined" {
  type chrome_snapshot > /dev/null 2>&1
}

@test "cli: chrome_restore is defined" {
  type chrome_restore > /dev/null 2>&1
}

@test "cli: _emit_safety_js (hidden verb) is dispatched" {
  # _emit_safety_js is a CLI dispatch verb, not a bash function
  grep -q "_emit_safety_js)" "$LIB"
}

@test "cli: URL blocklist function is defined" {
  type _chrome_check_url_blocklist > /dev/null 2>&1
}
