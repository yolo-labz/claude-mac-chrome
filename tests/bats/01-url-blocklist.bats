#!/usr/bin/env bats
# Feature 006 T038: URL blocklist bats test suite
# Per spec §FR-6 + NFR-V2-SAFETY (rail tested in isolation).
#
# Tests _chrome_check_url_blocklist function directly. No DOM, no
# osascript, no Chrome. Pure shell.

setup() {
  REPO_ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$REPO_ROOT/skills/chrome-multi-profile/chrome-lib.sh"
  # shellcheck disable=SC1090
  source "$LIB"
}

# ─── Positive matches (SHOULD block) ────────────────────────────────────

@test "blocklist: Proton upgrade URL is blocked" {
  _chrome_check_url_blocklist "https://account.proton.me/u/0/subscription/upgrade"
}

@test "blocklist: Proton dashboard URL is blocked" {
  _chrome_check_url_blocklist "https://account.proton.me/u/0/dashboard"
}

@test "blocklist: Stripe checkout subdomain is blocked" {
  _chrome_check_url_blocklist "https://checkout.stripe.com/pay/cs_test_abc123"
}

@test "blocklist: Stripe buy subdomain is blocked" {
  _chrome_check_url_blocklist "https://buy.stripe.com/14k28Y9Sp3qM7uo7ss"
}

@test "blocklist: PayPal checkout is blocked" {
  _chrome_check_url_blocklist "https://www.paypal.com/checkout/review"
}

@test "blocklist: Google Pay is blocked" {
  _chrome_check_url_blocklist "https://pay.google.com/gp/w/u/0/home/checkout"
}

@test "blocklist: Amazon buy path is blocked" {
  _chrome_check_url_blocklist "https://www.amazon.com/gp/buy/spc/handlers/display.html"
}

@test "blocklist: generic checkout path is blocked" {
  _chrome_check_url_blocklist "https://example.com/checkout/cart"
}

@test "blocklist: generic payment path is blocked" {
  _chrome_check_url_blocklist "https://example.com/payment/confirm"
}

@test "blocklist: generic billing path is blocked" {
  _chrome_check_url_blocklist "https://example.com/billing/subscription"
}

@test "blocklist: generic subscribe path is blocked" {
  _chrome_check_url_blocklist "https://example.com/subscribe/premium"
}

@test "blocklist: generic upgrade path is blocked" {
  _chrome_check_url_blocklist "https://example.com/upgrade/pro"
}

@test "blocklist: generic cart path is blocked" {
  _chrome_check_url_blocklist "https://example.com/cart/123"
}

@test "blocklist: Google signin is blocked" {
  _chrome_check_url_blocklist "https://accounts.google.com/signin/v2/identifier"
}

# ─── Negative matches (should ALLOW) ────────────────────────────────────

@test "blocklist: Gmail inbox is allowed" {
  ! _chrome_check_url_blocklist "https://mail.google.com/mail/u/0/#inbox"
}

@test "blocklist: GitHub home is allowed" {
  ! _chrome_check_url_blocklist "https://github.com/anthropic/claude-code"
}

@test "blocklist: example.com root is allowed" {
  ! _chrome_check_url_blocklist "https://example.com/"
}

@test "blocklist: localhost dev server is allowed" {
  ! _chrome_check_url_blocklist "http://localhost:3000/dashboard"
}

@test "blocklist: Classroom path is allowed" {
  ! _chrome_check_url_blocklist "https://classroom.google.com/c/NzgyMTkxNDMzODcy"
}

@test "blocklist: HN frontpage is allowed" {
  ! _chrome_check_url_blocklist "https://news.ycombinator.com/"
}

@test "blocklist: Wikipedia article is allowed" {
  ! _chrome_check_url_blocklist "https://en.wikipedia.org/wiki/Chrome_(browser)"
}

@test "blocklist: similar-but-safe URL (chase.com) is allowed" {
  # Note: chase.com is a bank but not on the blocklist (no checkout path).
  # This tests that the blocklist is URL-based, not domain-reputation-based.
  ! _chrome_check_url_blocklist "https://www.chase.com/personal/checking"
}

# ─── Edge cases ─────────────────────────────────────────────────────────

@test "blocklist: URL with trailing slash on upgrade is blocked" {
  _chrome_check_url_blocklist "https://account.proton.me/u/0/subscription/upgrade/"
}

@test "blocklist: URL with query string on checkout is blocked" {
  _chrome_check_url_blocklist "https://checkout.stripe.com/pay/cs_123?session=abc"
}

@test "blocklist: empty URL is not blocked (fails closed elsewhere)" {
  ! _chrome_check_url_blocklist ""
}

@test "blocklist: URL fragment on upgrade is blocked" {
  _chrome_check_url_blocklist "https://example.com/upgrade#plan-premium"
}
