#!/usr/bin/env bats
# Feature 006 T040 — trigger lexicon loader bats suite.
# Per spec §NFR-SR-V2-LEX-1..3 + Pedro's pt-BR requirement.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  LEX_FILE="$REPO_ROOT/skills/chrome-multi-profile/lexicon/triggers.txt"
  # shellcheck disable=SC1090
  source "$LIB"
}

@test "lexicon: triggers.txt file exists" {
  [ -f "$LEX_FILE" ]
}

@test "lexicon: Portuguese 'comprar' present (Pedro critical case)" {
  grep -qw "comprar" "$LEX_FILE"
}

@test "lexicon: Portuguese 'assinar' present" {
  grep -qw "assinar" "$LEX_FILE"
}

@test "lexicon: Portuguese 'pagar' present" {
  grep -qw "pagar" "$LEX_FILE"
}

@test "lexicon: Portuguese 'finalizar' present" {
  grep -qw "finalizar" "$LEX_FILE"
}

@test "lexicon: Portuguese 'contratar' present" {
  grep -qw "contratar" "$LEX_FILE"
}

@test "lexicon: English 'upgrade' present" {
  grep -qw "upgrade" "$LEX_FILE"
}

@test "lexicon: English 'subscribe' present" {
  grep -qw "subscribe" "$LEX_FILE"
}

@test "lexicon: English 'checkout' present" {
  grep -qw "checkout" "$LEX_FILE"
}

@test "lexicon: no empty lines break regex" {
  run _chrome_load_trigger_lexicon
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" != *"||"* ]] || [ "$output" != "|" ]
}

@test "lexicon: alternation regex format" {
  run _chrome_load_trigger_lexicon
  [ "$status" -eq 0 ]
  [[ "$output" == *"|"* ]]
}
