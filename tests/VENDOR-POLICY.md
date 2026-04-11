# Vendored Dependency Policy

**Scope:** `tests/vendor/` only. No runtime code vendors dependencies; the skill itself has zero runtime dependencies.

## Current vendors

| File | Upstream | Status |
|---|---|---|
| `tests/vendor/happy-dom.mjs` | https://github.com/capricorn86/happy-dom | Pinned — see `VENDOR-MANIFEST.json` |

## Refresh cadence

- **Routine:** Monthly review of pinned version against upstream releases.
- **Security:** Any `High` or `Critical` CVE affecting the vendored version forces a **7-day refresh window**. OSV-Scanner (see `.github/workflows/osv-scan.yml`) auto-files an issue.
- **Breaking:** If upstream changes API, follow the "stuck pin" runbook in `docs/VENDOR-RUNBOOK.md` (create or defer to a patched fork, NEVER inline-patch).

## Refresh ceremony

1. Update `upstream_version`, `upstream_commit`, `upstream_tarball_sha256` in `tests/VENDOR-MANIFEST.json`.
2. Run `scripts/verify-vendor.sh` to rebuild from scratch in a clean temp dir.
3. Commit the new `happy-dom.mjs` + manifest in the **same commit**.
4. Confirm `bundle_sha256` matches what CI produces via `.github/workflows/reproducibility.yml`.
5. Re-run `tests/run.sh` to ensure no fixture divergence.
6. Bump `HAPPY-DOM-FIDELITY.md` if any API semantics changed (e.g., new bug fixes landed that flip a `stubbed` row to `parity`).

## Byte-identical re-verification

Every CI run MUST re-derive the bundle in a clean environment and `diff` against the committed `happy-dom.mjs`. Any drift fails the build.

This is enforced by:
- `scripts/verify-vendor.sh` (local dev loop)
- `.github/workflows/reproducibility.yml` (CI)

## No inline patches

We do **not** inline-patch vendored code. If upstream has a bug we need fixed:
1. File it upstream
2. Pin to a branch/commit that has the fix (or our own fork)
3. Document the deviation in `VENDOR-MANIFEST.json::upstream_deviations`

Inline edits defeat byte-identical verification and create silent drift.
