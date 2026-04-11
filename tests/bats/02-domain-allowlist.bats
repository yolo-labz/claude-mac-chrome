#!/usr/bin/env bats
# Feature 006 T039 — domain allowlist bats suite.
# Per spec §FR-7 + NFR-SR-V2-18.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  # shellcheck disable=SC1090
  source "$LIB"
}

@test "allowlist: unset -> unrestricted (returns 0 for any domain)" {
  unset CHROME_LIB_ALLOWED_DOMAINS
  run _chrome_check_domain_allowlist "https://example.com/"
  [ "$status" -eq 0 ]
}

@test "allowlist: wildcard '*' refused (fail-closed per NFR-SR-V2-18)" {
  export CHROME_LIB_ALLOWED_DOMAINS="*"
  run _chrome_check_domain_allowlist "https://example.com/"
  [ "$status" -ne 0 ]
}

@test "allowlist: bare TLD refused" {
  export CHROME_LIB_ALLOWED_DOMAINS="com"
  run _chrome_check_domain_allowlist "https://example.com/"
  [ "$status" -ne 0 ]
}

@test "allowlist: exact domain match passes" {
  export CHROME_LIB_ALLOWED_DOMAINS="example.com"
  run _chrome_check_domain_allowlist "https://example.com/path"
  [ "$status" -eq 0 ]
}

@test "allowlist: subdomain suffix match passes" {
  export CHROME_LIB_ALLOWED_DOMAINS="example.com"
  run _chrome_check_domain_allowlist "https://api.example.com/v1"
  [ "$status" -eq 0 ]
}

@test "allowlist: unrelated domain refused" {
  export CHROME_LIB_ALLOWED_DOMAINS="example.com"
  run _chrome_check_domain_allowlist "https://attacker.com/"
  [ "$status" -ne 0 ]
}

@test "allowlist: comma-separated list matches any entry" {
  export CHROME_LIB_ALLOWED_DOMAINS="example.com,github.com,gmail.com"
  run _chrome_check_domain_allowlist "https://github.com/repo"
  [ "$status" -eq 0 ]
}

@test "allowlist: comma-separated list refuses non-member" {
  export CHROME_LIB_ALLOWED_DOMAINS="example.com,github.com"
  run _chrome_check_domain_allowlist "https://paypal.com/checkout"
  [ "$status" -ne 0 ]
}
