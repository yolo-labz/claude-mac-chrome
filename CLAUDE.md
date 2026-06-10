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

## Release engineering (yolo-labz standards) — repo-scoped canon

<!-- Moved here from the global Claude rules layer (NixOS spec 887 FR-012): policy is repo-scoped, not fleet-global. -->

Release-engineering standards for every self-coded Claude Code plugin in the
yolo-labz GitHub org (claude-mac-chrome, wa, kokoro-speakd, claude-classroom-submit,
homebrew-tap). Derived from ~/NixOS/meta/yolo-labz-release-engineering-research.md —
read it in full before any release-engineering work on these repos. Do NOT apply
these rules to unrelated projects.

## Supply chain (mandatory)

- Use GitHub native attestations: `actions/attest-build-provenance` +
  `actions/attest-sbom`. Current production pin across the yolo-labz rollout is
  v4.1.0, SHA `a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`. Pin both actions in
  full SHA-with-comment form, e.g.:
    `uses: actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32 # v4.1.0`
    `uses: actions/attest-sbom@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32 # v4.1.0`
  (the v2/v3/v4 family is acceptable; v4.1.0 is the current rollout standard).
  Do NOT add `slsa-framework/slsa-github-generator` to new work — only maintain
  it on claude-mac-chrome if the SLSA L3 formal claim is still load-bearing.
  New plugins get L2 + native attestations.
- Primary user verification path is `gh attestation verify` (single command, no
  cosign install). Demote `cosign verify-blob` + `slsa-verifier` to an "advanced
  / offline" README section, never the headline.
- Cosign OIDC issuer is `https://token.actions.githubusercontent.com`. The
  `https://github.com/login/oauth` URL is the interactive human flow, NOT CI.
- Publish BOTH CycloneDX 1.7 AND SPDX 2.3 SBOMs. `syft` emits both in one call:
  `syft . -o cyclonedx-json@1.7=sbom.cdx.json -o spdx-json=sbom.spdx.json`. For
  Go repos, additionally run `cyclonedx-gomod app -licenses -std -json` for a
  richer Go-native SBOM.
- Never re-tag a release. `slsa-verifier` validates against the commit SHA at
  signing time; re-tagging produces stale provenance. Cut `vX.Y.Z+1` on botched
  publishes.
- Always `export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)` before archive or
  build steps so tarballs and wheels are byte-reproducible.

## GitHub Actions hardening (mandatory)

- Pin every action by FULL 40-char commit SHA with a trailing `# vX.Y.Z` comment.
  Tag pins (even "immutable") do NOT satisfy Scorecard's Pinned-Dependencies.
  Dependabot preserves the version comment when bumping SHAs — never strip it.
- Workflow-level `permissions: {}` (deny-all), per-job re-grant. Signing jobs
  need `id-token: write` + `attestations: write` + `contents: read`. Add
  `contents: write` only if the same job cuts a GitHub Release, `packages: write`
  only for OCI pushes.
- Add `step-security/harden-runner@<sha>` in `egress-policy: audit` on every
  release workflow. Flip to `block` after one release cycle once Sigstore egress
  is observed. Linux full-support; macOS/Windows audit-only.
- Use Repository Rulesets, not classic branch protection. Bootstrap required
  checks via `enforcement: disabled` → merge → `active`. Delete classic
  protection AFTER ruleset verification — they stack additively and the stricter
  silently wins.
- Use reusable workflows (`workflow_call`), not composite actions, for shared
  release/signing logic. Caller job must still declare `id-token: write` —
  permissions intersect, not inherit upward.
- Add `zizmor` + `actionlint` as pre-commit hooks. Catches template-injection
  and permission mistakes CodeQL/Sonar miss.
- `persist-credentials: false` on `actions/checkout` unless pushing back.
- `timeout-minutes:` on every job.

## Language-specific (read research.md §3 for full detail)

Go (wa):
- GoReleaser OSS is sufficient; Pro is not needed for this stack.
- `-trimpath`, `-buildvcs=true` (Go 1.24 default), `CGO_ENABLED=0`, `-buildmode=pie`.
- `-ldflags=-X main.date={{.CommitDate}}` — commit timestamp, NEVER `$(date)`.
- Pin toolchain via `go.mod` `toolchain go1.24.x` directive.
- Drop standalone `govulncheck` when adding OSV-Scanner V2 — the latter invokes
  govulncheck internally for Go call-graph reachability; running both is
  redundant.
- `go test -race -shuffle=on -count=1 ./...` in CI; nightly fuzz with committed
  corpus under `testdata/fuzz/`.
- Use `brews:` (not `homebrew_casks:`) for CLIs in the tap.

Python (kokoro-speakd, claude-classroom-submit):
- Publish via PyPI Trusted Publishing (`pypa/gh-action-pypi-publish@release/v1`).
  PEP 740 attestations are auto-generated since v1.11 (Nov 2024). Do NOT add a
  separate `sigstore/gh-action-sigstore-python` step — redundant.
- Build backend: `hatchling` (or `uv_build` for speed). Set `SOURCE_DATE_EPOCH`
  plus `PYTHONHASHSEED=0` before `uv build`.
- Run `pip-audit` + `osv-scanner` + Dependabot in parallel; dedupe on GHSA alias.
- `ruff` replaces flake8/black/isort/pyupgrade/pydocstyle. Use `pyright` over
  mypy unless plugins force the issue.
- CodeQL Python uses `build-mode: none`; add `paths-ignore: ['site-packages/**']`
  for ML-heavy repos.
- kokoro-speakd: declare torch/onnxruntime as `>=` deps — do NOT build/ship your
  own torch wheels. Model weights ship as GitHub Release assets with
  `attest-build-provenance` over the file digest, not via PyPI.
- claude-classroom-submit: publish to PyPI anyway (trusted publishing + PEP 740
  attestations are free benefits even for zero-dep packages).

Shell (claude-mac-chrome):
- `#!/usr/bin/env bash` with bash 3.2 compatibility (macOS). Avoid `declare -A`,
  `mapfile`, `readarray`, `${var^^}`, `${var,,}`.
- CodeQL does NOT support shell in 2026. Upload ShellCheck SARIF separately via
  `github/codeql-action/upload-sarif`.
- Use `bats` + `shellcheck` + `shfmt` (community standard; Anthropic has no
  blessed framework).

## Governance (mandatory)

- `CHANGELOG.md` is auto-generated, never hand-edited. Either tool is acceptable:
  `git-cliff` (single Rust binary, no npm — preferred for Go repos like `wa`) or
  `release-please` (GitHub Action, supports monorepo, preferred for polyglot or
  greenfield plugin repos). Pick one per repo; don't mix. Output format follows
  Keep-a-Changelog 1.1.0.
- Conventional commits enforced via `commitlint` + `@commitlint/config-conventional`
  in `lefthook` (faster than husky; `wa` already uses this — match the pattern).
- Dependency updates: `Dependabot` (native GitHub, preserves `# vX.Y.Z` SHA-pin
  comments) OR `Renovate` (more aggressive, `helpers:pinGitHubActionDigests`
  preset). `wa` uses Renovate — respect existing choice, do not migrate.
- `SECURITY.md` points users at `/security/advisories/new` (GitHub Private
  Vulnerability Reporting). PGP keys are discouraged in 2026.
- `CODEOWNERS` is path-based (documents intent, eases future collaboration).
- DCO sign-off (`git commit -s`) for hygiene; no CLA.
- License: MIT or Apache-2.0, author's choice. `wa` is Apache-2.0 (explicit
  patent grant, matches Anthropic Telegram plugin precedent); other plugins
  are MIT. Do not migrate an existing license without discussion.

## Scorecard optimization

Realistic ceiling for a solo-dev yolo-labz repo is ~8.7/10:

- Fuzzing: `fuzz.yml` is NOT detected by Scorecard. For Go, add one `*_test.go`
  with `func FuzzX(f *testing.F)` — free +10. For shell, restructure to
  `.clusterfuzzlite/` + `.github/workflows/cflite_pr.yml`.
- Contributors: structurally capped ~3/10 for solo devs. Not gameable via
  Co-Authored-By trailers (bots and empty `Company` fields are filtered).
  Accept the loss and document in SECURITY.md.
- Maintained: auto-heals at day 90 with ≥1 commit/week.
- Packaging: add any publishing action (`softprops/action-gh-release`,
  `pypa/gh-action-pypi-publish`, `JS-DevTools/npm-publish`) → 10/10.
- Pinned-Dependencies: use StepSecurity's secure-workflow rewriter
  (https://app.stepsecurity.io/secureworkflow/) for bulk SHA pinning.
- Token-Permissions: `permissions: read-all` at workflow top-level → +2-3.
- Signed-Releases: Sigstore cosign + SLSA provenance assets → 10/10.

## Claude Code plugin ecosystem constraints (informational)

As of April 2026, Anthropic's Claude Code plugin marketplace has NO supply-chain
requirements (no signing, no SBOM, no SLSA, no signature verification on install).
Trust is per-marketplace, not per-plugin. Supply-chain work on yolo-labz plugins
is voluntary — good security hygiene, ahead-of-Anthropic. Do NOT block on
marketplace compliance when planning supply-chain rollouts.

- `plugin.json` lives at `.claude-plugin/plugin.json`; only `name` is required.
- `plugin.json` version field wins over marketplace entry version — pick one home.
- Persistent binary state lives in `CLAUDE_PLUGIN_DATA` (not CLAUDE_PLUGIN_ROOT).
- SessionStart hook pattern: diff a `manifest.lock` against bundled version,
  reinstall binary on drift, `chmod +x`, write new manifest. Do NOT re-download
  every session.
- No plugin-to-plugin dependency field exists; document required sibling plugins
  in README and check via SessionStart hook.
- Shell plugins must use `CLAUDE_PLUGIN_ROOT` for all paths; never bare relative.
- Hooks must exit non-zero with actionable error messages.

## Invariants (never break these)

1. Never re-tag a release. Cut vX.Y.Z+1 on botched publishes.
2. Never commit binaries to the repo (`dist/`, `build/` in `.gitignore`).
3. Never ship a release with failing CI. Tag push must be gated on green main.
4. Never store SonarQube `USER_TOKEN` credentials in CI. Always use
   `PROJECT_ANALYSIS_TOKEN` scoped to one project key.
5. Never use `--certificate-oidc-issuer https://github.com/login/oauth` in cosign
   docs — that is the interactive human flow. Use
   `https://token.actions.githubusercontent.com` for CI-issued OIDC.
6. Never edit `CHANGELOG.md` by hand once `release-please` owns it.
7. Never strip the `# vX.Y.Z` comment from SHA-pinned actions — Dependabot's
   regex needs it to recognize the entry.
8. TRANSITIVE-PIN: a top-level SHA pin is necessary but NOT sufficient. For any
   reusable-workflow / composite-action `uses:`, recursively verify every NESTED
   `uses:` in its call graph is SHA-pinned (it inherits the caller's secrets).
   Enforce with `meta/expand-uses.py --max-depth 5 --fail-on-mutable`.
9. AI-CI-INJECTION self-defense: never combine `pull_request_target`/`workflow_run`
   with a checkout of fork code while secrets are in scope; never interpolate
   `github.event.*` expressions into an agent prompt or a `run:` block (pass via
   `env:`, reference `"$VAR"`); treat agent output as untrusted code (no
   auto-exec/auto-merge). `zizmor --persona=auditor` is a REQUIRED PR gate.
10. OSPS Baseline is the SPEC (Level 1 floor -> Level 2 target); the ~8.7/10
    Scorecard ceiling is only the MEASUREMENT. When they disagree, OSPS wins.
11. AUDIT-BEFORE-BOOTSTRAP: baseline-report -> prioritized plan -> fix-in-PR ->
    re-run Scorecard -> log delta. P0 repo-settings (Code-Review, Branch-Protection,
    Maintained) before P1 automation (SAST, Pinned-Deps, Fuzzing). Fuzzing ships in
    its OWN PR. Never declare a repo "done" on intent — only on a logged delta.
12. Never close the issue/PR yourself (verify + report; the human closes). Frame
    bootstrap/audit runs as an "expert product security engineer"; prefer the `gh`
    CLI over the GitHub MCP on API limits. Weekly drift-audit via `meta/drift-audit.py`
    (a pinned SHA matching no upstream tag, or a SHRINKING tag set, is a probable
    tj-actions-style takeover — treat as P0). Full detail: rules 21-27 of
    `~/NixOS/meta/yolo-labz-release-engineering-research.md`.
