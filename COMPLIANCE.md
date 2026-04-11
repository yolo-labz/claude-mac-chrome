# Compliance Statement

**Project:** claude-mac-chrome
**Version:** 1.0.0 (planned GA)
**Statement date:** 2026-04-11
**Annual review:** 2027-04-11

## EU Cyber Resilience Act (CRA)

### Applicability determination

claude-mac-chrome is released as **free and open-source software with no commercial activity by the original author**. Per Article 3(18) of Regulation (EU) 2024/2847 and Recital 15, this project is **out of scope** of the CRA's mandatory obligations.

**Reasoning:**
- No person is paid to develop or maintain this project
- No commercial support is sold
- The project is distributed free of charge under the MIT License
- The author does not provide paid services related to the software
- The project accepts voluntary donations but does not condition access on them

### Upstream supplier disclaimer

If a third party **commercially repackages or distributes** claude-mac-chrome (e.g., as part of a paid enterprise bundle, paid support contract, or commercial marketplace listing), **that party becomes responsible for CRA obligations**, not the original author. The original author assumes no CRA liability for downstream commercial distributions.

### Voluntary posture

Even though out of scope, the project voluntarily adheres to the following CRA-aligned practices:

| Requirement | Implementation |
|---|---|
| Vulnerability handling policy | `SECURITY.md` — 72h acknowledge, 7d triage, 30/90d fix |
| Secure development practices | Spec-driven, shell hygiene gates, bats + fuzz + integration suites |
| SBOM (CycloneDX 1.7) | Published per release via `.github/workflows/release.yml` |
| Signed releases | cosign keyless via GitHub Actions OIDC |
| Reproducible builds | `scripts/build-release.sh` + `.github/workflows/reproducibility.yml` |
| CVE disclosure | Coordinated via GitHub Security Advisories |

## Voluntary vulnerability reporting timeline

| Phase | Target | Status |
|---|---|---|
| Acknowledgment | Within 24h | Manual, best-effort |
| Triage + severity | Within 72h | Manual |
| Fix or mitigation | Within 30d (Critical) / 90d (High) / best-effort (Medium/Low) | Manual |
| Public disclosure | Coordinated, after fix release | Via GitHub Security Advisory |

## Licensing + copyright

- License: MIT (see `LICENSE`)
- Copyright: © 2026 Pedro Henrique Souza Balbino + contributors
- Third-party content: see `tests/VENDOR-MANIFEST.json` for vendored happy-dom (MIT) used in tests only

## Privacy

- The project collects **zero telemetry** by default
- No analytics, no opt-in/opt-out dialogs, no network calls outside of Chrome's own behavior
- `docs/PRIVACY.md` (or root `PRIVACY.md`) contains the data-handling statement

## Export control

- No encryption primitives implemented
- No restricted technology transfer
- ECCN classification: not applicable (software is OSS and publicly available)
