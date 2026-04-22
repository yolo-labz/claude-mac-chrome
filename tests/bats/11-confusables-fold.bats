#!/usr/bin/env bats
# PR #20 — script-confusables fold (Cyrillic + Greek + Armenian Latin-lookalikes)
# plus combining-mark / BiDi-override / zero-width strip.
# Covers NFKC blind spot: distinct-script codepoints never decompose to Latin.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  PROBE="$REPO_ROOT/tests/js-fixtures/confusables-fold-probe.mjs"
  export LIB
}

_fold() {
  node "$PROBE" "$1"
}

@test "fold: ASCII passthrough" {
  [ "$(_fold 'upgrade')" = "upgrade" ]
}

@test "fold: Cyrillic 'р' (U+0440) → Latin 'p' in Upgrаde" {
  [ "$(_fold 'Upgrаde')" = "Upgrade" ]
}

@test "fold: Greek 'α' (U+03B1) → Latin 'a' in Upgrαde" {
  [ "$(_fold 'Upgrαde')" = "Upgrade" ]
}

@test "fold: Cyrillic 'с' (U+0441) → Latin 'c' in сheсkout" {
  [ "$(_fold 'сheсkout')" = "checkout" ]
}

@test "fold: Greek 'υ' (U+03C5) → Latin 'u' in sυbscribe" {
  [ "$(_fold 'sυbscribe')" = "subscribe" ]
}

@test "fold: zero-width U+200B inside 'buy' stripped" {
  [ "$(_fold $'b\u200Buy')" = "buy" ]
}

@test "fold: BiDi RLO U+202E stripped" {
  [ "$(_fold $'u\u202Epgrade')" = "upgrade" ]
}

@test "fold: combining acute via NFKD (café → cafe)" {
  [ "$(_fold 'café')" = "cafe" ]
}

@test "fold: fullwidth Latin folded via NFKD compatibility decomposition" {
  [ "$(_fold 'ｕｐｇｒａｄｅ')" = "upgrade" ]
}

@test "fold: uppercase Cyrillic 'Р' (U+0420) → Latin 'p' in uРgrade" {
  [ "$(_fold 'uРgrade')" = "upgrade" ]
}

@test "fold: unmapped Cyrillic 'б' (U+0431) stays (not in Latin confusables subset)" {
  [ "$(_fold 'бuy')" = "бuy" ]
}

@test "emit: fold map embedded in safety JS" {
  run bash "$LIB" _emit_safety_js ".any"
  [ "$status" -eq 0 ]
  [[ "$output" == *"_CONFUSABLES_FOLD"* ]]
  [[ "$output" == *"_foldConfusables"* ]]
  [[ "$output" == *'normalize("NFKD")'* ]]
}

@test "emit: fold applied at 3 call sites (norm_text + ancestor node_text + attr val)" {
  run bash "$LIB" _emit_safety_js ".any"
  [ "$status" -eq 0 ]
  count=$(printf '%s\n' "$output" | grep -c "_foldConfusables(")
  [ "$count" -ge 3 ]
}

@test "emit: zero-width strip regex present" {
  run bash "$LIB" _emit_safety_js ".any"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\\u200B-\\u200F"* ]]
}

@test "emit: combining-mark strip range present (U+0300-U+036F)" {
  run bash "$LIB" _emit_safety_js ".any"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\\u0300-\\u036F"* ]]
}

@test "emit: fold map has at least 60 entries (Cyrillic+Greek+Armenian coverage)" {
  run bash "$LIB" _emit_safety_js ".any"
  [ "$status" -eq 0 ]
  entries=$(printf '%s\n' "$output" | grep -oE '"\\u[0-9A-Fa-f]{4}":"[a-z0-9]"' | wc -l | tr -d ' ')
  [ "$entries" -ge 60 ]
}
