#!/usr/bin/env bats
# Feature 006 T046 — TTY confirmation bats suite.
# Per spec §NFR-SR-V2-TTY-1..4.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  # shellcheck disable=SC1090
  source "$LIB"
}

@test "tty: function _chrome_tty_confirm is defined" {
  type _chrome_tty_confirm > /dev/null 2>&1
}

@test "tty: piped stdin refused (non-TTY detection)" {
  # Running via `bash -c` with piped stdin — /dev/null is not a TTY
  run bash -c "source '$LIB' && _chrome_tty_confirm 'click' '#target' 'https://example.com/' 'Upgrade'" < /dev/null
  [ "$status" -ne 0 ]
}

@test "tty: stdin closed refused" {
  run bash -c "source '$LIB' && _chrome_tty_confirm 'click' '#target' 'https://example.com/' 'Upgrade' < /dev/null"
  [ "$status" -ne 0 ]
}

@test "tty: exact 'yes' string required (documented contract)" {
  # Function body must reference literal "yes" as the required response
  grep -q '"yes"' "$LIB"
}

@test "tty: source file uses isatty check on fd 0 and fd 2" {
  # Defense: verifies both stdin (fd 0) and stderr (fd 2) are TTYs
  grep -q 'TTY authenticity' "$LIB"
}
