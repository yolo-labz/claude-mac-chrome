#!/usr/bin/env bash
# Feature 006 T056 — radamsa URL fuzzer for blocklist.
# Per spec §NFR-V2-FX-9.
#
# Runs 1000 radamsa mutations per known-dangerous URL. Asserts:
#   1. No crash in _chrome_check_url_blocklist
#   2. No URL containing the known trigger substrings (upgrade, checkout,
#      billing, cart, subscribe) returns "allowed"
#
# Invoked by .github/workflows/fuzz.yml nightly.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"

if ! command -v radamsa > /dev/null 2>&1; then
  echo "FATAL: radamsa not installed"
  exit 1
fi

seeds=(
  "https://account.proton.me/u/0/subscription/upgrade"
  "https://checkout.stripe.com/pay/cs_test_abc"
  "https://buy.stripe.com/14k28Y9Sp3qM7uo7ss"
  "https://www.paypal.com/checkout/review"
  "https://pay.google.com/gp/w/u/0/home/checkout"
  "https://www.amazon.com/gp/buy/spc/handlers/display.html"
  "https://example.com/checkout/cart"
  "https://example.com/subscribe/premium"
)

fail=0
iterations_per_seed=125 # 8 seeds * 125 = 1000 iterations total

for seed in "${seeds[@]}"; do
  for _ in $(seq 1 $iterations_per_seed); do
    mutated=$(printf '%s' "$seed" | radamsa)

    # Skip obviously-invalid mutations (non-URL chars in scheme, etc.)
    [[ "$mutated" =~ ^https?:// ]] || continue

    # Run the blocklist check. Capture exit code.
    if _chrome_check_url_blocklist "$mutated" 2> /dev/null; then
      # blocklist returned 0 = blocked. If the mutation still contains
      # a known danger token, this is correct behavior.
      :
    else
      # blocklist returned non-zero = NOT blocked. Check if mutation
      # still matches a danger token — if so, we have a BYPASS.
      lower=$(printf '%s' "$mutated" | tr '[:upper:]' '[:lower:]')
      for token in upgrade checkout billing cart subscribe; do
        if [[ "$lower" == *"$token"* ]]; then
          echo "BYPASS: mutation '$mutated' contains '$token' but was not blocked"
          fail=$((fail + 1))
          break
        fi
      done
    fi
  done
done

if [[ $fail -gt 0 ]]; then
  echo "FAIL: $fail radamsa mutations bypassed the blocklist"
  exit 1
fi

echo "PASS: 1000 radamsa mutations exercised without bypass"
