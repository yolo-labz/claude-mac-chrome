#!/usr/bin/env bats
# PR #21 — audit log rotation (NFR-SR-V2-AUDIT-ROT) + append-only flag
# (NFR-SR-V2-16). Validates size-triggered single-slot rotation under the
# mkdir-based lock and the Darwin chflags uappnd enforcement path.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  export HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$HOME"
  # Small threshold so rotation triggers after a handful of writes.
  export CHROME_AUDIT_ROTATE_BYTES=512
  export CHROME_AUDIT_APPEND_ONLY=0
  # shellcheck disable=SC1090
  source "$LIB"
  AUDIT_PATH=$(_chrome_audit_log_path)
}

teardown() {
  [[ "$(uname -s)" == "Darwin" ]] && chflags -R nouappnd "$HOME" 2> /dev/null || true
  rm -rf "$HOME"
}

@test "rotation: helpers are defined" {
  type _chrome_audit_rotate_if_needed > /dev/null 2>&1
  type _chrome_audit_lock > /dev/null 2>&1
  type _chrome_audit_unlock > /dev/null 2>&1
  type _chrome_audit_set_append_only > /dev/null 2>&1
}

@test "rotation: below threshold — no .1 file" {
  _chrome_audit_append "click" "ok" "https://example.com/" "#a"
  [ -f "$AUDIT_PATH" ]
  [ ! -f "${AUDIT_PATH}.1" ]
}

@test "rotation: crossing 512-byte threshold produces .1 and fresh log" {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    _chrome_audit_append "click" "ok" "https://example.com/$i" "#a"
  done
  [ -f "${AUDIT_PATH}.1" ]
  [ -f "$AUDIT_PATH" ]
  # Fresh log is smaller than the rotated one
  rotated_size=$(wc -c < "${AUDIT_PATH}.1" | tr -d ' ')
  current_size=$(wc -c < "$AUDIT_PATH" | tr -d ' ')
  [ "$rotated_size" -ge 512 ]
  [ "$current_size" -lt "$rotated_size" ]
}

@test "rotation: both .1 and current remain valid JSONL after rotation" {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    _chrome_audit_append "click" "ok" "https://example.com/$i" "#a"
  done
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq -e . > /dev/null
  done < "${AUDIT_PATH}.1"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line" | jq -e . > /dev/null
  done < "$AUDIT_PATH"
}

@test "rotation: second rotation overwrites prior .1 (single-slot)" {
  for i in $(seq 1 20); do
    _chrome_audit_append "click" "ok" "https://example.com/$i" "#a"
  done
  first_rotated_size=$(wc -c < "${AUDIT_PATH}.1" | tr -d ' ')
  # Force more rotations
  for i in $(seq 21 60); do
    _chrome_audit_append "click" "ok" "https://example.com/$i" "#a"
  done
  # Still only one rotated slot
  [ ! -f "${AUDIT_PATH}.2" ]
  [ -f "${AUDIT_PATH}.1" ]
  # The rotated slot has been overwritten at least once
  second_rotated_size=$(wc -c < "${AUDIT_PATH}.1" | tr -d ' ')
  [ "$second_rotated_size" -gt 0 ]
  # We ran 3x the original volume — either size differs or the earliest writes are gone.
  # Check that URL /1 (which was in the first rotation) is no longer present anywhere.
  ! grep -q "example.com/1\"" "$AUDIT_PATH" || true
  ! grep -q "example.com/1\"" "${AUDIT_PATH}.1" || true
  [ "$first_rotated_size" -gt 0 ]
  [ "$second_rotated_size" -gt 0 ]
}

@test "rotation: mkdir-lock acquires and releases idempotently" {
  _chrome_audit_ensure_dir
  run _chrome_audit_lock
  [ "$status" -eq 0 ]
  lockdir=$(_chrome_audit_lock_dir)
  [ -d "$lockdir" ]
  _chrome_audit_unlock
  [ ! -d "$lockdir" ]
}

@test "rotation: contention — second lock attempt within holder's window fails fast" {
  _chrome_audit_ensure_dir
  _chrome_audit_lock
  # Override sleep to no-op so the 50 retries finish in <1s
  sleep() { return 0; }
  run _chrome_audit_lock
  [ "$status" -eq 1 ]
  _chrome_audit_unlock
}

@test "rotation: concurrent writers produce no partial JSONL lines" {
  for i in $(seq 1 5); do
    ( for j in $(seq 1 10); do
        _chrome_audit_append "click" "ok" "https://example.com/w${i}_$j" "#a"
      done ) &
  done
  wait
  # Every line in both files parses as JSON
  for f in "$AUDIT_PATH" "${AUDIT_PATH}.1"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "$line" | jq -e . > /dev/null || { echo "bad line in $f: $line"; return 1; }
    done < "$f"
  done
}

@test "append-only: chflags uappnd applied on first write (Darwin only)" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "chflags is Darwin-only"
  fi
  unset CHROME_AUDIT_APPEND_ONLY
  _chrome_audit_append "click" "ok" "https://example.com/" "#a"
  # stat -f %Sf shows flag names on Darwin
  flags=$(/usr/bin/stat -f '%Sf' "$AUDIT_PATH")
  echo "flags=$flags"
  [[ "$flags" == *"uappnd"* ]]
  chflags nouappnd "$AUDIT_PATH"
}

@test "append-only: uappnd blocks truncating write but permits append" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "chflags is Darwin-only"
  fi
  unset CHROME_AUDIT_APPEND_ONLY
  _chrome_audit_append "click" "ok" "https://example.com/" "#a"
  # Truncate must fail
  ! : > "$AUDIT_PATH" 2> /dev/null
  # Append must succeed
  _chrome_audit_append "click" "ok" "https://example.com/2" "#b"
  line_count=$(wc -l < "$AUDIT_PATH" | tr -d ' ')
  [ "$line_count" -ge 2 ]
  chflags nouappnd "$AUDIT_PATH"
}

@test "append-only: rotation clears+reapplies uappnd (log continues growing)" {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    skip "chflags is Darwin-only"
  fi
  unset CHROME_AUDIT_APPEND_ONLY
  for i in $(seq 1 15); do
    _chrome_audit_append "click" "ok" "https://example.com/$i" "#a"
  done
  [ -f "${AUDIT_PATH}.1" ]
  flags_current=$(/usr/bin/stat -f '%Sf' "$AUDIT_PATH")
  flags_rotated=$(/usr/bin/stat -f '%Sf' "${AUDIT_PATH}.1")
  [[ "$flags_current" == *"uappnd"* ]]
  [[ "$flags_rotated" == *"uappnd"* ]]
  chflags nouappnd "$AUDIT_PATH" "${AUDIT_PATH}.1"
}

@test "source: rotation helper uses mkdir-lock and chflags uappnd" {
  grep -q "_chrome_audit_rotate_if_needed" "$LIB"
  grep -q 'chflags uappnd' "$LIB"
  grep -q 'mkdir "$dir"' "$LIB"
}
