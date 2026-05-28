# CLAUDE.md — claude-mac-chrome

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Purpose

Chrome automation plugin for Claude Code on macOS. Two insights make it deterministic:

1. **Chrome's `Local State` JSON file is an authoritative profile catalog** — directory names, human display names, primary account emails. The library reads it; no user configuration needed.
2. **AppleScript exposes stable string IDs** for windows and tabs (`id of window w` returns `"100000001"`). These persist across z-order shuffles, tab reorders, and focus changes — unlike ordinals (`window 1`, `tab 5`), which drift silently and route Claude to the wrong profile.

Window-to-profile binding is built by extracting signed-in emails from Gmail/Drive/ProtonMail tab titles and matching them against the Local State catalog. The library is wrapped behind a 15-layer safety gauntlet on every `chrome_click` dispatch to make AI-driven purchase / submit / pair mistakes mechanically impossible.

## Stack

- **Language:** Bash 4.0+ (associative arrays + `mapfile`). macOS ships `/bin/bash` 3.2.57; the library refuses to run on it and prints `brew install bash` + PATH-export hints. CI runs on `macos-15` which provides bash 5.x via Homebrew.
- **Tooling:** AppleScript via `osascript` for window/tab control + JS dispatch; `cliclick` for coordinate-driven clicks; `jq` for JSON parsing; Python 3 (ships with macOS CLT) for `Local State` parsing.
- **Tests:** 14 bats files (1052 LOC), Playwright integration on `macos-15`, fuzz suite (radamsa URLs + html-grammar + 72-variant unicode-confusables), vendored happy-dom DOM-fidelity probes.
- **Platform:** macOS 13+; Intel + Apple Silicon. No Linux, no Windows by design — AppleScript is the mechanism.
- **License:** MIT.

## Repo layout

```text
.claude-plugin/
  plugin.json              # name, version, description (required by Claude Code)
  marketplace.json         # required by Claude Code v2.1.108+ for `/plugin marketplace add`
skills/
  chrome-multi-profile/
    SKILL.md               # invocation contract
    chrome-lib.sh          # the library — single file, zero deps beyond bash + osascript
    lexicon/triggers.txt   # purchase/subscribe/pair words (en + pt-BR)
    docs/                  # patterns.md, profile-detection.md
  chrome-workflows/
    check-emails/SKILL.md  # canned workflow
commands/
  chrome-debug.md          # /chrome-debug slash command
launch/                    # launchd plists for SessionStart bootstrap (future)
tests/
  bats/                    # 14 files — url blocklist, allowlist, lexicon, rate limiter,
                           # audit log, prompt injection, tty confirm, cli surface,
                           # confusables fold, audit rotation, toctou fingerprint, js async
  integration/             # Playwright on macos-15 (clickjack, dialog-inert,
                           # positive-dispatch, pseudo-element, visibility)
  bench/run.sh             # p50/p95/p99 latency for 6 ops vs docs/benchmarks/v*.json
  fuzz/                    # radamsa + html-grammar + unicode-confusables
  vendor/                  # happy-dom vendored bundle (audited via VENDOR-POLICY.md)
  fixtures/                # goldens.lock pins schema-stable fixtures
docs/
  benchmarks/v1.0.0.json   # perf SLO baseline
  benchmarks/v1.1.1.json   # current baseline (post supply-chain hardening)
  THREAT-MODEL.md          # asset/adversary/mitigation matrix
  HAPPY-DOM-FIDELITY.md    # divergence from real DOM
  MIGRATION-0.x-to-1.0.md  # breaking-change guide
  RELEASE.md               # release-ceremony runbook
  api.md                   # public CLI surface
scripts/
  build-release.sh         # SOURCE_DATE_EPOCH tarball + SBOM dual + SLSA attest + cosign
  release-tag.sh           # tag ceremony
  regenerate-goldens.sh    # goldens-lock refresh (workflow-gated)
  verify-vendor.sh         # vendor SBOM + happy-dom integrity check
  lint.sh                  # shellcheck + shfmt
flake.nix                  # dev shell (bash, bats, shellcheck, shfmt, jq, cosign, syft)
.github/workflows/         # 14 jobs — release, bench, codeql, sonar, scorecard,
                           # osv-scan, fuzz, cflite, integration, reproducibility,
                           # no-ai-slips, parity-canary, nix-flake-check
```

## Run / build / test

```bash
bats tests/bats/                       # 14-file bats suite (1052 LOC)
bash tests/integration/run.sh          # Playwright integration — macos-15 only
bash tests/bench/run.sh                # p50/p95/p99 latency for 6 ops
nix develop                            # pinned dev shell (bash, bats, shellcheck, jq, cosign, syft)
bash scripts/build-release.sh          # reproducible tarball + dual SBOM + SLSA + cosign
bash scripts/lint.sh                   # shellcheck + shfmt
bash scripts/verify-vendor.sh          # vendor SBOM + happy-dom integrity
```

CI matrix (`.github/workflows/`):

- `release.yml` — GoReleaser-equivalent ceremony: `actions/attest-build-provenance` + `actions/attest-sbom` (currently being pinned to `v4.1.0` in PR #63 alongside the existing SLSA L3 generator), CycloneDX 1.7 + SPDX 2.3 SBOMs.
- `bench.yml` — Performance gate: any tag whose p50/p95/p99 regresses >20% versus `docs/benchmarks/v1.1.1.json` fails the release.
- `reproducibility.yml` — Byte-identical tarball verification via `diffoscope`.
- `scorecard.yml` — OpenSSF Scorecard weekly run; target ≥ 7.0.
- `cflite_pr.yml` + `cflite_cron.yml` — ClusterFuzzLite layout for Scorecard Fuzzing credit.
- `codeql.yml` — SAST on Actions + JS/TS. Shell SARIF is uploaded separately (CodeQL has no shell support in 2026).
- `parity-canary.yml` — Bash 4.0+ parity check between macos-15 + ubuntu-latest.

## Conventions

- **Bash 4.0+ baseline.** Library refuses to run on macOS stock `/bin/bash` 3.2.57. Uses `mapfile` + `local -A`. Apple Silicon + Intel install paths documented in README.
- **Conventional Commits + DCO + Co-Author trailer.** Enforced via `lefthook` (added in PR #64) + `commitlint`.
- **Worktree-first** — every PR authored in `~/Documents/Code/yolo-labz-claude-mac-chrome-NNN-slug/`. Main worktree stays on `main`, clean, forever.
- **Release tags `vX.Y.Z`.** Tag push triggers `.github/workflows/release.yml`. **Never re-tag** — `slsa-verifier` validates against the commit SHA at signing time; re-tagging produces stale provenance. Cut `vX.Y.Z+1` on botched publishes.
- **Goldens locked in `tests/fixtures/goldens.lock`.** Regenerate only via the dedicated workflow + `scripts/regenerate-goldens.sh` — never hand-edit.
- **Performance gate:** any release whose `bench/run.sh` regresses >20% on p50/p95/p99 versus the latest committed `docs/benchmarks/v*.json` fails release CI.
- **`CHANGELOG.md` is auto-generated.** Owned by `git-cliff` per `cliff.toml` (added in PR #64). Never hand-edit.

## Architecture

`skills/chrome-multi-profile/chrome-lib.sh` is the single-file library that Claude Code invokes. Five public CLI verbs cover the surface:

| Verb | Purpose |
|---|---|
| `catalog` | Dump `Local State` profile catalog as JSON (every profile on this machine) |
| `fingerprint` | Scan open windows, extract emails from tab titles, return `{by_dir, by_email}` mapping |
| `window_for <ref>` | Resolve a profile by display name / email / profile-dir / substring → stable window ID |
| `tab_for_url <win> <substr>` | Find the first tab in a window whose URL contains `<substr>` |
| `js <win> <tab> <code>` | Run JavaScript in `(tab id "..." of window id "...")` via osascript |
| `navigate <win> <tab> <url>` | Set the URL of a specific tab |
| `new_tab <win> <url>` | Create a new tab in a window, return its stable ID |
| `js_async <win> <tab> <code>` | Await a Promise via title-sentinel pattern (per-call random `__cmc_<16hex>`) |
| `click <win> <tab> <selector>` | Trigger a click that traverses the **15-layer safety gauntlet** before dispatch |
| `refresh` | Invalidate the on-disk fingerprint cache (after Chrome restart or window open/close) |
| `debug` | Human-readable diagnostic — surfaced via `/chrome-debug` slash command |

The companion plugin `yolo-labz/linkedin-chrome-copilot` delegates 100% of Chrome I/O to this library via its `tools/chrome-shim.sh`. Treat that as the reference downstream consumer when changing the public CLI surface.

## Safety gauntlet (15 layers)

Every `chrome_click` traverses all 15 layers in `_chrome_safety_check_js` before AppleScript ever dispatches the click. Layers are ordered to fail-fast on cheap checks:

1. **URL blocklist** — page URL must not match known purchase/checkout/auth domains (`tests/bats/01-url-blocklist.bats`).
2. **Domain allowlist** — if `CHROME_DOMAIN_ALLOWLIST` is set, the page must be on it (`tests/bats/02-domain-allowlist.bats`).
3. **Trigger lexicon (en + pt-BR)** — target text and 3-ancestor walk are scanned for purchase/subscribe/pair tokens (`comprar`, `assinar`, `pagar`, `finalizar`, `contratar`, etc.) per `lexicon/triggers.txt`.
4. **Unicode normalization + zero-width strip** — NFKC + remove `U+200B`/`U+200C`/`U+200D`/`U+FEFF` before lexicon match.
5. **TR39 script-confusables fold** — `_foldConfusables(s)` (NFKD → combining-mark strip → 79-codepoint Cyrillic/Greek/Armenian → Latin map) closes the NFKC blind spot where `U+0430` Cyrillic `а` renders identically to Latin (`tests/bats/11-confusables-fold.bats` + `tests/fuzz/unicode-confusables.mjs` 72/72).
6. **Shadow DOM walker** — descends open shadow roots when extracting text.
7. **Pseudo-element extractor** — reads `::before`/`::after` content via `getComputedStyle`.
8. **Payment field lock** — refuses to click ANY button on a page with a credit-card input (defense-in-depth).
9. **Inert container check** — refuses clicks on elements inside `[inert]` ancestors.
10. **Visibility + zero-dim check** — element must be visible + non-zero bounding box.
11. **Clickjack hit-test** — `elementFromPoint(centerX, centerY)` must return the target or a descendant.
12. **Rate limiter** — per-verb cap (default 10 clicks/60s) with mkdir-mutex serialization (`tests/bats/04-rate-limiter.bats`).
13. **Audit log** — every dispatch + every block written as JSONL to `~/Library/Logs/claude-mac-chrome/audit.jsonl` (mode 0600, `chflags uappnd` append-only on Darwin, single-slot rotation at 10 MiB — `tests/bats/05-audit-log.bats` + `12-audit-rotation.bats`).
14. **TTY confirmation gate** — purchases/subscriptions require `--confirm-purchase=<exact text>` AND a TTY prompt (`tests/bats/09-tty-confirm.bats`).
15. **TOCTOU element fingerprint** — `{tag, id, outerHTML_hash (FNV-1a 32-bit), rect}` snapshotted in `_chrome_safety_check_js`, re-verified in the dispatch JS after `el.isConnected`; any drift on tag/id/hash or rect >4 px returns `{ok:false, error:"toctou_drift"}` (`tests/bats/13-toctou-fingerprint.bats`). Closes the race where an attacker mutates the DOM after safety-pass but before click.

Prompt-injection scanner (layer 0, prerequisite) sweeps the target's text + attributes for known injection markers before the gauntlet runs (`tests/bats/06-prompt-injection.bats`).

Full asset/adversary matrix in `docs/THREAT-MODEL.md`.

## Cross-references

- **Vault canon:** `~/.claude/CLAUDE.md`, `~/Documents/Code/CLAUDE.md` (workspace org rules).
- **Constitution:** `~/Documents/Code/yolo-labz/.specify/memory/constitution.md` v1.0.0 (Principles I–XV, all non-negotiable).
- **Audit:** [`phsb5321/notes-work#24`](https://github.com/phsb5321/notes-work/pull/24).
- **Spec:** `024-yolo-labz-portfolio-consolidation-2026Q2`.
- **Compliance:** [`COMPLIANCE.md`](./COMPLIANCE.md) — CRA Article 3(18) out-of-scope determination + voluntary alignment.
- **Threat model:** [`docs/THREAT-MODEL.md`](./docs/THREAT-MODEL.md).
- **Benchmarks:** [`docs/benchmarks/v1.1.1.json`](./docs/benchmarks/v1.1.1.json) — current performance SLO baseline.
- **Sibling repo (LinkedIn delegate):** [`yolo-labz/linkedin-chrome-copilot`](https://github.com/yolo-labz/linkedin-chrome-copilot) — consumes `chrome-lib.sh` via `tools/chrome-shim.sh`.

## Active feature work pointers

- **Open PRs:**
  - [#63](https://github.com/yolo-labz/claude-mac-chrome/pull/63) — `feat(release): add native attest-build-provenance@v4.1.0 alongside SLSA L3 generator`. Pins `actions/attest-build-provenance` + `actions/attest-sbom` to `v4.1.0` (SHA `a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`) per yolo-labz release-engineering plan.
  - [#64](https://github.com/yolo-labz/claude-mac-chrome/pull/64) — `chore(dev): lefthook + cliff.toml + shellcheck SARIF`. Adopts `lefthook` for pre-commit/commit-msg/pre-push, `git-cliff` for CHANGELOG ownership, and ShellCheck SARIF upload via `github/codeql-action/upload-sarif` (CodeQL has no shell support).

## Release verification

```bash
# Primary path — GitHub native attestations (single command, no cosign install needed)
gh attestation verify ./claude-mac-chrome.tar.gz \
  --repo yolo-labz/claude-mac-chrome \
  --signer-workflow yolo-labz/claude-mac-chrome/.github/workflows/release.yml
```

Advanced / offline verification (`cosign verify-blob` + `slsa-verifier`) documented in [`README.md` → Verifying releases → Advanced](./README.md#verifying-releases) and [`SECURITY.md` → Release verification](./SECURITY.md#release-verification). Cosign OIDC issuer is always `https://token.actions.githubusercontent.com` (the `github.com/login/oauth` URL is the interactive human flow — never use it in CI docs).

If ANY verification fails: **do not install**, file a GitHub Security Advisory.

## License

MIT — see [LICENSE](./LICENSE).
