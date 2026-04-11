# GitHub Actions Pin Lock

**Purpose:** Track every pinned action SHA in workflow files. Per spec §NFR-V2-PIN-1.

Every `uses:` entry in `.github/workflows/*.yml` MUST be pinned to a 40-char commit SHA with a trailing `# v<x.y.z>` comment. This file documents each pin for auditability.

## Pinned actions inventory

| Action | Pinned SHA | Version | Purpose |
|---|---|---|---|
| `actions/checkout` | `11bd71901bbe5b1630ceea73d27597364c9af683` | v4.2.2 | Checkout source in every job |
| `actions/setup-node` | `39370e3970a6d050c480ffad4ff0ed4d3fdee5af` | v4.1.0 | Node.js installation |
| `actions/upload-artifact` | `b4b15b8c7c6ac21ea08fcf65892d2ee8f75cf882` | v4.4.3 | Upload job artifacts |
| `actions/download-artifact` | `fa0a91b85d4f404e444e00e005971372dc801d16` | v4.1.8 | Download job artifacts |
| `actions/github-script` | `60a0d83039c74a4aee543508d2ffcb1c3799cdea` | v7.0.1 | Inline JS for issue filing |
| `google/osv-scanner-action/osv-scanner-action` | `f0ef35cea29c3c5e0797701b0c44f6e8db7e9b16` | v1.9.2 | Vendored dep CVE scanner |
| `ossf/scorecard-action` | `62b2cac7ed8198b15735ed49ab1e5cf35480ba46` | v2.4.0 | OpenSSF Scorecard |
| `github/codeql-action/upload-sarif` | `662472033e021d55d94146f66f6058822b0b39fd` | v3.27.0 | SARIF upload to code-scanning |
| `anchore/sbom-action` | `df80a981bc6edbc4e220a492d3cbe9f5547a6e75` | v0.17.4 | CycloneDX 1.7 SBOM |
| `sigstore/cosign-installer` | `dc72c7d5c4d10cd6bcb8cf6e3fd625a9e5e537da` | v3.7.0 | cosign install for keyless signing |
| `softprops/action-gh-release` | `c062e08bd532815e2082a85e87e3ef29c3e6d191` | v2.0.8 | Create GitHub Release |
| `slsa-framework/slsa-github-generator` | `v2.0.0` (reusable workflow, version-pinned) | v2.0.0 | SLSA L3 provenance |

## Refresh procedure

Dependabot (`.github/dependabot.yml`) opens PRs for action updates. Maintainer reviews + merges manually:

1. Dependabot opens PR updating SHA + comment
2. Review the upstream diff for the action version
3. Update this file with the new SHA
4. Merge PR
5. Monitor next workflow run for regressions

## SLSA reusable workflow exception

`slsa-github-generator` is pinned to a tag (`v2.0.0`) rather than a SHA per SLSA project guidance. GitHub's reusable workflow spec requires the same repo@ref for provenance attestation. Document deviation: the SLSA generator itself is SLSA L3 attested, creating a chain of trust.
