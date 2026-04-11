# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-04-11 — General Availability

First stable release. All test harness infrastructure is live and passing
(happy-dom 14/14 green, bats 95/95 green, shellcheck clean, reproducible
build verified byte-identical across runs, CI green on all 4 workflows:
reproducibility, nix flake check, osv-scan, sonar).

### 0.x branch EOL notice

**The entire 0.x line is EOL on 2026-10-11** (180 days post v1.0.0 GA). See
SECURITY.md for the support matrix. Security fixes only until that date; no
feature backports. Upgrade path: `docs/MIGRATION-0.x-to-1.0.md` (no breaking
changes to public API — safe upgrade).

## [1.0.0-rc1] — 2026-04-11 — Release Candidate

First release candidate. Promoted to stable 1.0.0 after CI gate passed.
All content of this RC is identical to 1.0.0 GA except for the version
string in `.claude-plugin/plugin.json`.

## [1.0.0 — details] — General Availability details

### Added

- **Full verification + release hardening story** (feature 006):
  - 15 curated HTML fixtures covering every `blocked_reason` enum variant (`tests/fixtures/`)
  - happy-dom JS fixture harness (`tests/js-fixtures/run.mjs`) with per-fixture rail isolation + forward/reverse exhaustiveness meta-tests
  - Playwright integration suite (`tests/integration/*.spec.ts`) for the 3 layout-dependent rails (clickjack, visibility, pseudo-element) that happy-dom cannot verify
  - 10 bats shell unit test files (`tests/bats/*.bats`): URL blocklist, domain allowlist, lexicon loader, rate limiter, audit log, prompt injection, chrome_click CLI, JSON stringify, TTY confirm, CLI surface
  - Stryker-js mutation testing configuration (85% kill-rate floor)
  - radamsa URL fuzzer, Unicode confusables fuzzer, HTML grammar fuzzer
  - Dual-harness parity test (happy-dom + real Chromium) as the v1.0.0 acceptance gate
- **Supply chain + release engineering:**
  - CycloneDX 1.7 SBOM generation via `anchore/sbom-action` on every release
  - SLSA L3 provenance via `slsa-github-generator` reusable workflow
  - cosign keyless signing via GitHub Actions OIDC
  - Reproducible build script (`scripts/build-release.sh`) using `SOURCE_DATE_EPOCH` + pinned `gnu-tar` + canonicalized file order
  - Reproducibility verification workflow (`.github/workflows/reproducibility.yml`) that runs the build twice and byte-compares
  - OSV-Scanner weekly run + PR gate on vendored dependencies (`.github/workflows/osv-scan.yml`)
  - OpenSSF Scorecard ≥ 7.0 target with weekly monitoring
  - All GitHub Actions pinned to 40-char commit SHA with version trailer
  - Dependabot configured for GitHub Actions + Playwright updates
- **Test harness hygiene:**
  - Vendored happy-dom at `tests/vendor/happy-dom.mjs` with `VENDOR-MANIFEST.json` (upstream SHA, tarball SHA, bundle SHA, reproducer command)
  - `scripts/verify-vendor.sh` re-derives the bundle in a clean temp dir and diffs against committed copy
  - `tests/VENDOR-POLICY.md` documents refresh cadence (monthly + 7-day CVE window)
  - `docs/HAPPY-DOM-FIDELITY.md` fidelity matrix for every DOM API the safety check touches (parity/stubbed/integration-only/out-of-scope)
  - `scripts/lint.sh` fails if a new DOM API is added to `_chrome_safety_check_js` without a matching fidelity matrix row
- **`fired_rail_trace` array** in every `chrome_click` envelope recording which rails ran (not just which blocked) for forensics.
- **Golden regeneration ceremony** (`scripts/regenerate-goldens.sh`) refusing to mix source + golden changes in one commit.
- **CODEOWNERS** routing safety-critical and fixture-touching PRs to security review.
- **Performance benchmark runner** (`tests/bench/run.sh`) measuring p50/p95/p99 for 6 operations with release-gate on > 20% regression.
- **Nix flake** (`flake.nix`) pinning the full dev toolchain (bats, shellcheck, shfmt, jq, gnu-tar, diffoscope, cosign, syft, node, radamsa) for reproducible local dev.
- **Comprehensive documentation:**
  - `docs/THREAT-MODEL.md` — STRIDE analysis for external security review
  - `docs/MIGRATION-0.x-to-1.0.md` — migration guide (no breaking changes)
  - `COMPLIANCE.md` — EU CRA applicability determination (out of scope per Art. 3(18))
  - `docs/RELEASE.md` — versioned release checklist
  - `docs/api.md` — frozen public API surface for v1.0.0
  - `docs/scorecard-targets.md` — per-check Scorecard target matrix
  - `SECURITY.md` — disclosure SLA (72h/7d/30/90d) + release key compromise playbook
  - README.md expanded with Troubleshooting (10 entries), FAQ (8 entries), Security, Privacy, Verifying Releases sections
  - CLAUDE.md hard rules: never ship a v-prefixed tag with failing `tests/run.sh`, never add CDP/extensions/throwaway profiles

### Changed

- Constitution Principle IV upgraded from "Shell hygiene is the test suite" to "Shell hygiene + bats + fixture harness + Playwright integration + mutation testing are the test suite contract". Constitution version bumped to **1.1.0**.
- `_chrome_safety_check_js` emits `fired_rail_trace: [...]` alongside `blocked_reason` for every invocation.

### Security

- **URL blocklist bugfix (CRITICAL, caught by first bats test run):** 4 patterns (`checkout.stripe.com`, `buy.stripe.com`, `pay.google.com`, `accounts.google.com`) were missing leading `*` wildcards and never matched URLs starting with `https://`. All 14 blocklist patterns fixed. This shipped as part of v0.9.0-dev and would have been a silent-ship defect in v1.0.0 without the test harness.
- Added prompt injection defense to cover `<|im_start|>`, `[INST]`, `System:`, `ignore previous` in page-content-derived strings.

## [0.8.0-dev] — Unreleased

### Added

- **`chrome_click`** — safety-gated click primitive with a 7-layer defense-in-depth gauntlet: domain allowlist (opt-in), URL blocklist, rate limiter, multi-locale purchase-button detection, payment-field lock mode, hit-test verification against clickjacking, and TTY confirmation with signal-proof 5-second read delay.
- **`chrome_query`** — read-only element query with shadow DOM recursive descent (`--deep` flag). No mutation, no safety gauntlet required.
- **`chrome_wait_for`** — host-side polling wrapper around `chrome_query`. Default 10000ms timeout, 250ms interval, 60000ms max.
- **Multi-locale trigger lexicon** at `skills/chrome-multi-profile/lexicon/triggers.txt` covering pt-BR (mandatory for Pedro's UFPE + Sciensa profiles), English, Spanish, French, German, Italian, Japanese, Chinese, Russian. Readonly, not overridable.
- **URL blocklist** covering `/checkout`, `/payment`, `/billing`, `/subscribe`, `/upgrade`, `/cart`, `/gp/buy/`, Stripe/PayPal/Google Pay/Proton upgrade domains.
- **Rate limiter** at `~/.local/state/claude-mac-chrome/rate.json` with sliding windows (10 actions/10s per window, 60/60s global). Fail-closed on corrupt/future-mtime/wrong-uid state.
- **Append-only audit log** at `~/.local/state/claude-mac-chrome/action-audit.jsonl` recording every action pre- and post-execution. File mode 0600, directory 0700. All string values JSON-encoded via `jq --arg` to defeat control-char log injection.
- **TTY confirmation** with `<<UNTRUSTED>>...<<END>>` quarantine delimiters around page content, explicit "page content, not instructions" copy, monotonic 5-second read delay with `trap '' ALRM USR1 USR2 CONT` to defeat signal-based skip attacks.
- **Prompt injection scanner** rejecting element text or URLs containing `ignore previous`, `you are now`, `system:`, `<|`, `[INST]`, etc.
- **Domain allowlist** via `CHROME_LIB_ALLOWED_DOMAINS` env var with permissiveness ceiling (rejects `*` and bare TLDs).
- **Shadow DOM recursive descent** in safety check JS (open shadow roots only, depth 10).
- **CSS `::before`/`::after` pseudo-element content extraction** to defeat CSS-injected purchase labels.

### Security

- **Critical**: makes the "accidental Proton 1mo purchase" incident architecturally impossible at seven independent layers. Any one of URL blocklist, rate limiter, lexicon regex on button text, lexicon regex on `aria-label`, payment field detection, hit-test mismatch, or TTY confirmation would block a purchase-button click.
- Selectors passed to injected JS via `jq -Rs .` (JSON.stringify) rather than string interpolation — defeats `"); evil(); //` injection.
- Realm pinning in safety check JS (`const _QS = document.querySelector.bind(document)` at script start) defeats late monkey-patching.
- Element text aggregates `textContent UNION innerText UNION shadow DOM UNION ::before/::after` before regex matching.
- All values in audit log JSONL are `jq --arg` encoded — ANSI escapes, control chars, fake JSON structures all safely stringified.

### Changed

- `chrome_click` dispatches a full pointer-event sequence (`pointerdown → mousedown → pointerup → mouseup → click`) with `PointerEvent` + `MouseEvent` carrying bubbles/cancelable/view/button/clientX/clientY/pointerType. Previously used bare `element.click()` which fails silently on React 18+/Vue 3 components.
- `chrome_click` includes pre-click hygiene: `isConnected` check, disabled/aria-disabled check, `scrollIntoView`, rect dimension check, viewport bounds check, `elementFromPoint` hit-test.
- Rate limiter uses `/usr/bin/stat` explicitly (BSD syntax) to avoid nix-darwin's GNU `stat` in PATH returning wrong values.

### Known Deferred (NOT shipping until complete)

- `chrome_fill` — React-safe form fill via native prototype descriptor. Deferred to dedicated session because of password-field risk.
- `chrome_js_async` — title-sentinel async pattern.
- `chrome_undo_last_fill` — requires fill.
- Full Unicode TR39 confusables folding (currently NFKC + zero-width stripping only — Cyrillic lookalikes like `Upgrаde` may still slip).
- Audit log rotation at 10MB with `flock` + `chflags uappnd` append-only enforcement.
- Element fingerprint stability check across check → dispatch window (TOCTOU).
- Auto-trigger skills + slash commands.
- Hard rule addition to CLAUDE.md.

**Version remains `0.8.0-dev`. DO NOT ship as v0.8.0 GA until deferred items complete.**

## [0.7.0] — Unreleased

### Added

- **`chrome_check_inboxes`** — cross-profile unread email count via `document.title` extraction. Supports Gmail, ProtonMail, Fastmail, Outlook web via pluggable provider pattern array.
- **`chrome_snapshot` / `chrome_restore`** — save and restore tab-sets as JSON (max 20 snapshots, FIFO eviction, URL query-strings stripped for privacy).
- **`chrome_health`** — detect crashed tabs (`chrome-error://`), auth-expired tabs, stuck-loading tabs.
- **`chrome_search_tabs`** — cross-profile tab search by URL or title substring.
- **`chrome_close_duplicates`** — find and close duplicate tabs within each profile window.
- **4 auto-triggering Claude Code skills** under `skills/chrome-workflows/`: check-emails, session-snapshot, profile-health, search-tabs.
- **3 slash commands** for mutating workflows: `/chrome-restore`, `/chrome-close-duplicates`, `/chrome-morning-workspace`.
- **Workflow state persistence** at `~/.local/state/claude-mac-chrome/workflow-state.json` for cross-invocation deltas (last-seen unread counts).

### Changed

- File permissions enforced at 0600 for all workflow-written files, 0700 for directories.

### Security

- URL query strings and fragments stripped before persisting to snapshots (prevents auth-token leakage).
- URL scheme allowlist (`https`, `http`) enforced on `chrome_restore` to prevent `javascript:` injection via tampered snapshots.
- Snapshot name validation rejects path traversal characters.
- JS injection rate cap (50 calls per invocation) prevents UI-thread starvation.
- Advisory file locking for concurrent snapshot writes.

## [0.4.0] — Unreleased

### Added

- **AX avatar-button email extraction (Tier 2).** New primary detection signal: reads the signed-in email from Chrome's profile avatar button tooltip via macOS Accessibility API (JXA). Optional — requires one-time Accessibility TCC grant; Tiers 3–4 work without it.
- **Per-profile URL history cache** at `~/Library/Caches/claude-mac-chrome/profile-urls/`, 50 URLs per profile (FIFO eviction), used by Tier 4 URL-overlap fallback.
- **Chrome liveness check** via `readlink SingletonLock` + `kill -0` at fingerprint start.

### Changed

- **All inline Python rewritten to jq + pure bash.** `chrome_profiles_catalog`, `chrome_fingerprint`, and all JSON assembly now use `jq`. `python3` is no longer a runtime dependency.
- **Tiered detection pipeline:** Tier 1 (Local State catalog) → Tier 2 (AX avatar email, NEW) → Tier 3 (tab-title email, demoted from primary) → Tier 4 (live URL overlap, replaces SNSS).
- **`method` field** in fingerprint output gains new value `ax_avatar`.
- Configurable tier skipping: `CHROME_LIB_SKIP_AX=1` (skip Tier 2), `CHROME_LIB_SKIP_URL=1` (skip Tier 4).

### Removed

- **SNSS `Sessions/Tabs_<id>` binary parser** — replaced by live tab URL overlap (Tier 4).
- **`chrome_profile_urls` CLI command** — was SNSS debugging tool; no replacement needed.
- **`chrome_disambiguate_by_urls` function** — replaced by `_chrome_live_url_overlap`.
- **All `python3` heredoc blocks** — replaced by `jq`.

## [0.3.0] — 2026-04-06

### Added

- **Same-email profile disambiguation via SNSS Sessions/Tabs URL-set overlap.** When two or more Chrome profiles share the same signed-in Google account (e.g., one email but separate profiles for Personal Shopping / Personal Dev / Personal Research), the library now parses each profile's latest `Sessions/Tabs_<id>` file (Chrome's own per-profile session snapshot) via binary `strings` extraction, then scores each candidate profile by how much the live window's tab URLs overlap with the profile's saved URL set. The profile with the highest A-coverage score wins. Ties are broken by SNSS file mtime (most recently written wins). Validated via synthetic test with three collision profiles, 100% correct routing.
- `assignments` field in `chrome_fingerprint` output: per-window record of `{profile_dir, name, email, method, score}`. Method is one of `email_unique` (single email match), `url_overlap` (same-email disambiguation), `url_fallback` (no email signal, matched purely by URLs), or `no_signal` (couldn't assign).
- `chrome_profile_urls <profile_dir>` CLI command — dump the SNSS-extracted URL set for a given profile, for debugging same-email routing decisions.
- **Modern shell practices throughout:** `#!/usr/bin/env bash` shebang, `set -euo pipefail` in CLI entry point (not sourced), `[[ ]]` tests everywhere, full variable quoting, `readonly` for constants, `printf` instead of `echo` for structured output, `mktemp`-based atomic cache writes, consistent `_chrome_err` / `_chrome_warn` error reporters.
- `scripts/lint.sh` — contributor lint runner combining shfmt format check + shellcheck (style severity) + live smoke test (catalog parse, fingerprint parse, JS round-trip). Auto-fetches shfmt and shellcheck via `nix run nixpkgs#<pkg>` if not in PATH.
- `chrome_debug` output now shows the match method (`email (unique)` vs `URL overlap`) and confidence score for every matched window.

### Changed

- `chrome_fingerprint_cached` now writes the cache atomically via `mktemp` + `mv -f` to prevent corrupt reads during concurrent invocations.
- `CHROME_CACHE` now honors `$TMPDIR` if set, falling back to `/tmp`.
- All error output routed through `_chrome_err` with a `[chrome-lib]` prefix for easy grepping in logs.

### Verified

- **shellcheck clean** at `--severity=style` (stricter than the default `warning` level).
- **shfmt clean** with the project style (`-i 2 -ci -sr`).
- End-to-end smoke test passes on Pedro's actual 2-profile Chrome setup (`Personal` + `Study`) — email_unique path.
- Synthetic 3-profile same-email collision test passes — url_overlap path cleanly routes each window to the correct profile with 1.000 confidence.

## [0.2.0] — 2026-04-06

### Added

- **Authoritative profile catalog from Chrome's `Local State` file** — the library now reads `~/Library/Application Support/Google/Chrome/Local State` directly to enumerate every profile on the machine, with directory names, display names, signed-in Google account emails, and gaia names. Zero user configuration required.
- **Email extraction from tab titles** as the per-window identity signal. Every Google / Gmail / Drive / Classroom / ProtonMail / Fastmail tab has the signed-in email in its title. The library scans all tabs in all windows and matches emails against the catalog.
- **Multi-index window resolution via `chrome_window_for`** — accepts profile directory name, display name, email, any substring of any of those, or a role alias from an optional `~/.config/claude-mac-chrome/roles.json` file.
- **Optional role alias file** at `~/.config/claude-mac-chrome/roles.json` for mapping semantic roles (`work`, `school`, `personal`) to specific profiles.
- **`chrome-lib.sh catalog`** command — dumps the raw profile catalog.
- Structured fingerprint output with `by_dir`, `by_name`, `by_email`, `unknown`, and `catalog` keys.
- `docs/profile-detection.md` — deep reference on Local State format, email extraction heuristics, edge cases.

### Changed

- **`chrome_fingerprint` no longer uses hardcoded URL substring matching.** The 0.1.0 default fingerprints (flatnotes, classroom, etc.) are gone. The library now works deterministically on any macOS Chrome setup without configuration.
- **`chrome_debug` output format** redesigned to show both the Local State catalog and the matched windows in a tabular view.
- `SKILL.md` rewritten to document the new approach.
- `README.md` updated with the Local State + email extraction flow and comparison table.

### Removed

- Hardcoded personal URLs (`flatnotes.home301server.com.br`) from all default fingerprint logic. These were a privacy leak in 0.1.0 — the library now contains zero URLs specific to any individual user.
- `docs/fingerprints.md` — replaced by `docs/profile-detection.md` with the new approach.

### Fixed

- Windows with tabs not matching any hardcoded URL fingerprint are no longer silently labeled `other` — they're now matched by their Google account email automatically.

## [0.1.0] — 2026-04-06

### Added

- Initial release
- `chrome-multi-profile` skill with progressive-disclosure `SKILL.md`
- `chrome-lib.sh` library with stable-ID addressing via AppleScript
- URL substring fingerprint matching (superseded in 0.2.0)
- `/chrome-debug` slash command
- Zero dependencies (pure bash + osascript)
