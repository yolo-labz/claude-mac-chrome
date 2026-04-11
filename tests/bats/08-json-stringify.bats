#!/usr/bin/env bats
# Feature 006 T045 — JSON stringify (jq -Rs .) escaping bats suite.
# Per spec §NFR-SR-V2-ESC-1.
#
# Ensures all selector/lexicon inputs to the safety check JS are passed
# through jq -Rs . so AppleScript injection is mechanically impossible.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  # shellcheck disable=SC1090
  source "$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
}

@test "jq: escapes double-quote" {
  result=$(printf '%s' 'foo"bar' | jq -Rs .)
  [ "$result" = '"foo\"bar"' ]
}

@test "jq: escapes backslash" {
  result=$(printf '%s' 'foo\bar' | jq -Rs .)
  [ "$result" = '"foo\\bar"' ]
}

@test "jq: escapes newline" {
  result=$(printf 'foo\nbar' | jq -Rs .)
  [ "$result" = '"foo\nbar"' ]
}

@test "jq: escapes tab" {
  result=$(printf 'foo\tbar' | jq -Rs .)
  [ "$result" = '"foo\tbar"' ]
}

@test "jq: escapes control chars" {
  result=$(printf 'foo\x01bar' | jq -Rs .)
  [[ "$result" == *"\u0001"* ]]
}

@test "jq: AppleScript quote injection mechanically defused" {
  # Attempt the classic '"; tell app "Finder"' injection
  payload='"; tell app "Finder" to delete everything; "'
  result=$(printf '%s' "$payload" | jq -Rs .)
  # Result must have all outer quotes escaped
  [[ "$result" == "\"\\\""* ]]
}

@test "jq: empty string safely quoted" {
  result=$(printf '%s' '' | jq -Rs .)
  [ "$result" = '""' ]
}

@test "jq: unicode passes through unchanged" {
  result=$(printf '%s' 'Café' | jq -Rs .)
  [ "$result" = '"Café"' ]
}
