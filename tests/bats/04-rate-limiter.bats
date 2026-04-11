#!/usr/bin/env bats
# Feature 006 T041 — rate limiter bats suite.
# Per spec §NFR-SR-V2-RATE-1..6.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  export HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$HOME"
  # shellcheck disable=SC1090
  source "$LIB"
}

teardown() {
  rm -rf "$HOME"
}

@test "rate: function _chrome_rate_check is defined" {
  type _chrome_rate_check > /dev/null 2>&1
}

@test "rate: function _chrome_rate_state_path is defined" {
  type _chrome_rate_state_path > /dev/null 2>&1
}

@test "rate: empty window_id is refused (fail-closed)" {
  run _chrome_rate_check ""
  [ "$status" -ne 0 ]
}

@test "rate: state path is under \$HOME/.local/state/claude-mac-chrome/" {
  run _chrome_rate_state_path
  [[ "$output" == "$HOME/.local/state/claude-mac-chrome/rate.json" ]]
}

@test "rate: corrupt JSON state fails closed" {
  state_path=$(_chrome_rate_state_path)
  mkdir -p "$(dirname "$state_path")"
  printf 'not valid json' > "$state_path"
  chmod 0600 "$state_path"
  run _chrome_rate_check "window-1"
  [ "$status" -ne 0 ]
}

@test "rate: source file declares version 1 schema" {
  grep -q '"version":1' "$LIB"
}
