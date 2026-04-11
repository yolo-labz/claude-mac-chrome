# Security Policy

## Supported versions

| Version | Supported | EOL |
|---|---|---|
| 1.0.x | ✅ Active | — |
| 0.8.x | ⚠️ Security fixes only | 2026-10-11 (180 days post v1.0.0) |
| 0.7.x | ⚠️ Security fixes only | 2026-10-11 |
| 0.6.x and older | ❌ End-of-life | 2026-04-11 |

**0.x branch EOL policy:** The entire 0.x line receives security fixes only for 180 days after the v1.0.0 GA tag. After 2026-10-11, no further 0.x releases will be made; users on 0.x are strongly encouraged to upgrade to 1.0.x via `docs/MIGRATION-0.x-to-1.0.md`.

## Reporting a vulnerability

**Do not file public GitHub issues for security vulnerabilities.** Instead, use GitHub's private vulnerability reporting:

1. Go to https://github.com/yolo-labz/claude-mac-chrome/security/advisories/new
2. Fill in the form with a description, reproducer, and impact assessment
3. Click "Submit report"

Alternatively, email `pedrobalbino@proton.me` with `[SECURITY] claude-mac-chrome` in the subject line. Do not include exploit code in the initial email — we'll ask for it over a secure channel after acknowledgment.

## Disclosure timeline (SLA)

| Phase | Target |
|---|---|
| Acknowledgment | Within 72 hours of receipt |
| Triage + severity assignment | Within 7 days |
| Fix or mitigation (Critical) | Within 30 days |
| Fix or mitigation (High) | Within 90 days |
| Fix or mitigation (Medium/Low) | Best-effort, next minor release |
| Public disclosure | Coordinated, after fix release |

## Scope

### In scope

- The `skills/chrome-multi-profile/chrome-lib.sh` library and its helper functions
- The 15-layer safety gauntlet in `_chrome_safety_check_js`
- URL blocklist, domain allowlist, rate limiter, audit log
- TTY confirmation gate + prompt injection scanner
- Trigger lexicon completeness (especially pt-BR — Pedro's critical locale)
- Supply chain: GitHub Actions pins, vendored happy-dom, cosign signature verification

### Out of scope

- Chrome browser vulnerabilities — report to Google directly
- macOS Apple Events permission bypass — report to Apple
- Claude Code / Claude API vulnerabilities — report to Anthropic
- Third-party web content (website XSS, etc.) that the library merely observes
- User misconfiguration (e.g., running as root, disabling TCC)

## Release verification

Every v1.0.0+ release is signed via cosign keyless OIDC and ships with a SLSA L3 provenance attestation + CycloneDX 1.7 SBOM. Verify before installing:

```bash
# Download release artifacts
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/download/v1.0.0/claude-mac-chrome.tar.gz
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/download/v1.0.0/claude-mac-chrome.tar.gz.sigstore
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/download/v1.0.0/SHA256SUMS

# Verify hash
shasum -a 256 -c SHA256SUMS

# Verify cosign signature
cosign verify-blob \
  --certificate-identity-regexp 'https://github.com/yolo-labz/claude-mac-chrome/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --bundle claude-mac-chrome.tar.gz.sigstore \
  claude-mac-chrome.tar.gz

# Verify SLSA L3 provenance
slsa-verifier verify-artifact claude-mac-chrome.tar.gz \
  --provenance-path claude-mac-chrome.tar.gz.intoto.jsonl \
  --source-uri github.com/yolo-labz/claude-mac-chrome \
  --source-tag v1.0.0
```

If ANY verification fails, **do not install**. File a security advisory immediately.

## Release key compromise playbook

If the cosign/Fulcio signing chain is suspected compromised:

1. **Immediate:** Mark the affected release(s) as withdrawn in GitHub Releases
2. **Immediate:** Post a `SECURITY_ADVISORY` notice at the top of README.md
3. **Within 24h:** File a public GitHub Security Advisory with the affected version range
4. **Within 72h:** Search Rekor transparency log for unexpected entries signed with the compromised identity (https://search.sigstore.dev/)
5. **Within 7d:** Rotate the GPG key used to sign `SHA256SUMS.asc` and publish the new public key fingerprint via:
   - This file
   - Announcement post (Reddit, HN, Twitter)
   - README.md
6. **Within 14d:** Re-sign and republish affected releases with the new identity
7. **Within 30d:** Post-mortem report + updated threat model in `docs/THREAT-MODEL.md`

Because cosign keyless uses ephemeral certificates from Fulcio, there is no long-lived signing key to rotate in the traditional sense. Compromise would instead mean:
- A GitHub Actions OIDC token was leaked (rotate repo secrets, audit workflow_run history)
- The maintainer's GitHub account was compromised (rotate MFA, audit personal access tokens)

## Hall of fame

_(Empty — file a report to be listed.)_
