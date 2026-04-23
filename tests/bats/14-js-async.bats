#!/usr/bin/env bats
# PR #23 — chrome_js_async (title-sentinel pattern).

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  export LIB
  # shellcheck disable=SC1090
  source "$LIB"
}

@test "cli: chrome_js_async is defined" {
  type chrome_js_async > /dev/null 2>&1
}

@test "cli: chrome_tab_title is defined" {
  type chrome_tab_title > /dev/null 2>&1
}

@test "cli: _chrome_js_async_wrapper helper is defined" {
  type _chrome_js_async_wrapper > /dev/null 2>&1
}

@test "cli: dispatch routes 'js_async' and 'tab_title'" {
  grep -q 'js_async) chrome_js_async' "$LIB"
  grep -q 'tab_title) chrome_tab_title' "$LIB"
}

@test "invalid args: missing win/tab/js returns INVALID_ARGS" {
  run chrome_js_async "" "" ""
  [ "$status" -eq 2 ]
  [[ "$output" == *'"error":"INVALID_ARGS"'* ]]
}

@test "invalid args: non-integer timeout rejected" {
  run chrome_js_async "win" "tab" "return 1;" "not-a-number"
  [ "$status" -eq 2 ]
  [[ "$output" == *'"error":"INVALID_ARGS"'* ]]
  [[ "$output" == *"timeout_s"* ]]
}

@test "invalid args: timeout out of range (0 and >600) rejected" {
  run chrome_js_async "win" "tab" "return 1;" 0
  [ "$status" -eq 2 ]
  run chrome_js_async "win" "tab" "return 1;" 601
  [ "$status" -eq 2 ]
}

@test "wrapper: embeds sentinel and emits resolve/reject paths" {
  run bash "$LIB" _emit_js_async_wrapper "MYSENTINEL" "return 1;"
  [ "$status" -eq 0 ]
  [[ "$output" == *'MYSENTINEL'* ]]
  [[ "$output" == *'__cmc_sentinel'* ]]
  [[ "$output" == *'Promise.resolve()'* ]]
  [[ "$output" == *'__cmc_emit({ok:true, value:'* ]]
  [[ "$output" == *'__cmc_emit({ok:false, error:'* ]]
}

@test "wrapper: stashes original title in window var for restore" {
  run bash "$LIB" _emit_js_async_wrapper "SENT" "return 1;"
  [ "$status" -eq 0 ]
  [[ "$output" == *'window["__cmc_orig_" + __cmc_sentinel] = document.title'* ]]
}

@test "wrapper: body injection of user JS is inside function IIFE (scoped)" {
  run bash "$LIB" _emit_js_async_wrapper "SENT" "var x = 7; return x + 1;"
  [ "$status" -eq 0 ]
  [[ "$output" == *'return (function(){ var x = 7; return x + 1; })()'* ]]
}

@test "source: wrapper-oneline tr conversion present" {
  grep -q "wrapper_oneline=.*tr '.n'" "$LIB"
}

@test "source: polling uses chrome_tab_title + sleep 0.1" {
  grep -q 'chrome_tab_title "\$win" "\$tab"' "$LIB"
  grep -q 'sleep 0.1' "$LIB"
}

@test "source: cleanup JS restores title and deletes window var" {
  grep -q "document.title = window\['__cmc_orig_'" "$LIB"
  grep -q "delete window\['__cmc_orig_'" "$LIB"
}

@test "probe: happy-dom wrapper cases pass" {
  if [[ ! -f "$REPO_ROOT/tests/vendor/happy-dom.mjs" ]]; then
    skip "happy-dom vendor missing"
  fi
  run node "$REPO_ROOT/tests/js-fixtures/js-async-wrapper-probe.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS sync return"* ]]
  [[ "$output" == *"PASS async Promise"* ]]
  [[ "$output" == *"PASS Promise.reject"* ]]
  [[ "$output" == *"PASS synchronous throw"* ]]
  [[ "$output" == *"ALL PASSED"* ]]
}
