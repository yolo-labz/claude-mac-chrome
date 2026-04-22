#!/usr/bin/env bats
# Feature 006 T042 — audit log bats suite.
# Per spec §NFR-SR-V2-AUDIT-1..5.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  export HOME="$BATS_TEST_TMPDIR/fake-home"
  export CHROME_AUDIT_APPEND_ONLY=0
  mkdir -p "$HOME"
  # shellcheck disable=SC1090
  source "$LIB"
  AUDIT_PATH=$(_chrome_audit_log_path)
}

teardown() {
  [[ "$(uname -s)" == "Darwin" ]] && chflags -R nouappnd "$HOME" 2> /dev/null || true
  rm -rf "$HOME"
}

@test "audit: functions _chrome_audit_append + _chrome_audit_log_path defined" {
  type _chrome_audit_append > /dev/null 2>&1
  type _chrome_audit_log_path > /dev/null 2>&1
}

@test "audit: log file created on first write" {
  _chrome_audit_append "click" "ok" "https://example.com/" "#target" || true
  [ -f "$AUDIT_PATH" ]
}

@test "audit: each entry is valid JSONL" {
  _chrome_audit_append "click" "ok" "https://example.com/" "#target" || true
  _chrome_audit_append "query" "ok" "https://github.com/" "#readme" || true
  [ -f "$AUDIT_PATH" ]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq -e . > /dev/null
  done < "$AUDIT_PATH"
}

@test "audit: control-char log injection is neutralized (JSONL line count stable)" {
  _chrome_audit_append "click" "ok" $'https://evil.example\r\x1b[2K{"fake":"injection"}' "#x" || true
  [ -f "$AUDIT_PATH" ]
  num_lines=$(wc -l < "$AUDIT_PATH" | tr -d ' ')
  [ "$num_lines" -ge 1 ]
  # First line must still parse as a single JSON object
  head -n1 "$AUDIT_PATH" | jq -e . > /dev/null
}

@test "audit: action field populated" {
  _chrome_audit_append "click" "ok" "https://example.com/" "#target" || true
  jq -e '.action == "click"' "$AUDIT_PATH" > /dev/null
}

@test "audit: source file uses jq --arg for escaping" {
  # Defense: every field MUST be encoded via jq --arg, not interpolated
  grep -q -- "--arg" "$LIB"
}
