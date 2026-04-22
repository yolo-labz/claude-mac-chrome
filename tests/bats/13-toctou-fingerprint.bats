#!/usr/bin/env bats
# PR #22 — TOCTOU element fingerprint (NFR-SR-V2-TOCTOU).
# Structural coverage: envelope carries fingerprint, dispatch JS includes
# the drift comparison, bash layer parses and surfaces toctou_drift.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  export LIB
}

@test "emit: safety JS embeds _fnv1a + element_fingerprint" {
  run bash "$LIB" _emit_safety_js "#target"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_fnv1a"* ]]
  [[ "$output" == *"element_fingerprint"* ]]
  [[ "$output" == *"outerHTML_hash"* ]]
}

@test "emit: fingerprint object shape includes tag/id/outerHTML_hash/rect" {
  run bash "$LIB" _emit_safety_js "#target"
  [ "$status" -eq 0 ]
  [[ "$output" == *'tag: el.tagName'* ]]
  [[ "$output" == *'id: el.id'* ]]
  [[ "$output" == *'outerHTML_hash: _fnv1a'* ]]
  [[ "$output" == *'rect: {'* ]]
}

@test "source: chrome_click injects _EXPECTED_FP into dispatch JS" {
  grep -q 'const _EXPECTED_FP = ${expected_fp};' "$LIB"
}

@test "source: chrome_click recomputes fingerprint in dispatch JS" {
  grep -q '_cur_fp.outerHTML_hash' "$LIB"
  grep -q 'drift.push("outerHTML_hash")' "$LIB"
  grep -q 'drift.push("rect")' "$LIB"
}

@test "source: bash layer routes toctou_drift to SAFETY_BLOCK + audit" {
  grep -q '"error":"toctou_drift"' "$LIB"
  grep -q '"reason":"toctou_drift"' "$LIB"
  grep -q '_chrome_audit_append "click" "blocked" .*"toctou_drift"' "$LIB"
}

@test "source: rect tolerance is 4px (layout jitter allowance)" {
  grep -qE 'Math.abs\(.*_cur_fp.rect.x.*\).*> 4' "$LIB"
  grep -qE 'Math.abs\(.*_cur_fp.rect.h.*\).*> 4' "$LIB"
}

@test "source: expected_fp extracted via jq -c .element_fingerprint" {
  grep -q "jq -c '.element_fingerprint" "$LIB"
}

@test "probe: happy-dom TOCTOU cases pass" {
  if [[ ! -f "$REPO_ROOT/tests/vendor/happy-dom.mjs" ]]; then
    skip "happy-dom vendor missing"
  fi
  run node "$REPO_ROOT/tests/js-fixtures/toctou-drift-probe.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS case 1"* ]]
  [[ "$output" == *"PASS case 2"* ]]
  [[ "$output" == *"PASS case 3"* ]]
  [[ "$output" == *"PASS case 4"* ]]
  [[ "$output" == *"ALL PASSED"* ]]
}
