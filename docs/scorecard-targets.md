# OpenSSF Scorecard Target Matrix

**Target floor score:** 7.0 / 10
**Measurement cadence:** Weekly via `.github/workflows/scorecard.yml`
**Release gate:** any score below 7.0 blocks the `v*` tag release pipeline per `docs/RELEASE.md`.

## Per-check targets

| Check | Target | How we meet it |
|---|---|---|
| Binary-Artifacts | 10 | No binaries committed to repo. `tests/vendor/happy-dom.mjs` is text JS, not binary. |
| Branch-Protection | 10 | `main` branch protected: required PR review, required status checks (lint + test + reproducibility), no direct push. |
| CI-Tests | 10 | Every PR runs lint, bats, fuzz, reproducibility. `scripts/lint.sh` is authoritative. |
| CII-Best-Practices | ≥ 5 | Registered at bestpractices.dev, achieved "passing" tier. Gold tier aspirational. |
| Code-Review | ≥ 3 | Waived via scorecard-config.yml maintainer-annotation (solo project). Fixture/safety PRs use CODEOWNERS audit trail. |
| Contributors | N/A | Scorecard skips this for repos with < 3 external contributors. |
| Dangerous-Workflow | 10 | No `pull_request_target` on PRs with write tokens. No `${{ github.event.* }}` in `run:` blocks. Enforced by lint. |
| Dependency-Update-Tool | 10 | Dependabot configured (`.github/dependabot.yml`) for GitHub Actions pins + nix flake.lock. |
| Fuzzing | 10 | radamsa URL fuzzer + HTML grammar fuzzer + Unicode confusables fuzzer run nightly. `tests/fuzz/`. |
| License | 10 | MIT license file at repo root. SPDX identifier in every source file. |
| Maintained | 10 | Recent commits + closed issues in past 90 days. |
| Packaging | 10 | Published via GitHub Releases with SLSA provenance + cosign signature. |
| Pinned-Dependencies | 10 | ALL GitHub Actions pinned to 40-char SHA. Vendored happy-dom pinned via manifest SHA. |
| SAST | ≥ 5 | shellcheck on all shell, CodeQL on workflows. |
| SBOM | 10 | CycloneDX 1.7 SBOM generated per release via `anchore/sbom-action`. |
| Security-Policy | 10 | `SECURITY.md` at repo root with disclosure SLA + contact + key compromise playbook. |
| Signed-Releases | 10 | cosign keyless via GitHub Actions OIDC + SLSA L3 attestation. |
| Token-Permissions | 10 | Every workflow has top-level `permissions: contents: read`. Job-level escalation only where strictly needed + documented inline. |
| Vulnerabilities | 10 | OSV-Scanner weekly on vendored deps; auto-file issue on findings. |
| Webhooks | N/A | No webhook triggers used. |

## Aggregate score computation

Scorecard uses a weighted average across checks. We target ≥ 7.0 with the above per-check floors, giving headroom for temporary dips (e.g., during dependency transition windows).

## What to do when a check drops

1. Check `.github/workflows/scorecard.yml` run logs for the failing check
2. If it's a known waiver case: add reasoning to `.github/scorecard-config.yml`
3. If it's a real regression: open a P1 issue tagged `scorecard`
4. Do NOT tag a new release while Scorecard < 7.0 — the release pipeline will refuse to run
