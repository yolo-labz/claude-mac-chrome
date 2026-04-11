# Release Checklist

Versioned release checklist for claude-mac-chrome. Run through this before creating any signed `v*` tag.

## Pre-release

- [ ] All open PRs for the target release are merged
- [ ] `CHANGELOG.md` has a section for the new version with: Added, Changed, Security, Breaking subsections populated
- [ ] `.claude-plugin/plugin.json` `version` field matches the target tag (no `-dev` suffix)
- [ ] `tests/run.sh` passes locally with zero failures
- [ ] `shellcheck -x skills/**/*.sh` passes
- [ ] `shfmt -d skills/` shows no diffs
- [ ] Playwright integration suite green in latest `integration.yml` run
- [ ] Parity canary (`parity-canary.yml`) has green run from past 7 days
- [ ] OSV-Scanner shows zero `High` or `Critical` findings on vendored deps
- [ ] OpenSSF Scorecard score ≥ 7.0 on latest scan

## Reproducibility check

- [ ] Run `scripts/build-release.sh /tmp/rel-a.tar.gz`
- [ ] Run `scripts/build-release.sh /tmp/rel-b.tar.gz` in a fresh temp dir
- [ ] `shasum -a 256 /tmp/rel-a.tar.gz /tmp/rel-b.tar.gz` — hashes must match byte-for-byte
- [ ] If mismatch: DO NOT TAG. Debug via `diffoscope /tmp/rel-a.tar.gz /tmp/rel-b.tar.gz`

## Benchmark regression check

- [ ] `bash tests/bench/run.sh > /tmp/new-bench.json`
- [ ] Compare against `docs/benchmarks/<previous-version>.json` — no SLO should regress > 20%

## Tag creation

- [ ] `git tag -s vX.Y.Z -m "vX.Y.Z — <tagline>"` (GPG signed, never lightweight)
- [ ] `git push origin vX.Y.Z`

## Post-tag verification

Wait for `.github/workflows/release.yml` to complete, then:

- [ ] Download the published tarball
- [ ] `cosign verify-blob --bundle <name>.sigstore <name>.tar.gz` succeeds
- [ ] `gpg --verify SHA256SUMS.asc SHA256SUMS` succeeds
- [ ] Re-run `scripts/build-release.sh` in a clean temp dir and compare its SHA to the published SHA
- [ ] Download SBOM (`sbom.cdx.json`) and spot-check the component list
- [ ] Verify SLSA provenance attestation (`claude-mac-chrome.tar.gz.intoto.jsonl`) via `slsa-verifier`

## Announcements

- [ ] Update marketplace entry at `platform.claude.com/plugins/submit` with new version number + changelog link
- [ ] Post to Reddit `r/ClaudeCode`
- [ ] Post to HN if MAJOR version
- [ ] Tweet/X announcement
- [ ] Update project README badge

## Rollback procedure

If a critical bug is found post-release:

1. Revert the release branch to the previous good tag
2. Create a new patch tag (NEVER force-push or delete the original tag — cosign + SBOM provenance would be orphaned)
3. Mark the broken release as a GitHub "prerelease" with a warning note
4. File a SECURITY.md advisory if the bug has security impact
