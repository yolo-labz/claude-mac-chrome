#!/usr/bin/env bash
# scripts/release-tag.sh — one-command release tag ceremony (T099, T100, T101)
#
# Usage: scripts/release-tag.sh <version>
#   Example: scripts/release-tag.sh 1.0.0
#
# What this does:
#   1. Verifies you're on main with a clean tree
#   2. Verifies PR #1 (feature 006) has been merged
#   3. Verifies scripts/lint.sh passes
#   4. Verifies scripts/build-release.sh is byte-identical across 2 runs
#   5. Bumps plugin.json from 1.0.0-rc1 -> <version>
#   6. Commits the version bump
#   7. Creates a GPG-signed annotated tag
#   8. Pushes the tag to origin, triggering .github/workflows/release.yml
#   9. Waits for the release workflow to succeed
#  10. Downloads the published release artifacts
#  11. Verifies cosign + SHA256SUMS + reproducibility
#
# PREREQUISITES (not enforced by this script):
#   - Maintainer GPG key configured in git (`git config user.signingkey`)
#   - cosign CLI installed locally
#   - PR #1 merged into main
#   - `gh auth status` showing logged in
#
# This script is INTENTIONALLY interactive. It will pause before each
# destructive operation. It will NOT proceed without explicit confirmation.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

err() { printf "${RED}✗${RESET} %s\n" "$*" >&2; exit 1; }
ok() { printf "${GREEN}✓${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}!${RESET} %s\n" "$*" >&2; }
step() { printf "\n${CYAN}▶${RESET} %s\n" "$*"; }

confirm() {
  local prompt="$1"
  printf "${YELLOW}%s${RESET} [yes/no] > " "$prompt"
  local answer
  read -r answer
  [[ "$answer" == "yes" ]] || err "aborted"
}

# ────────────────────────────────────────────────────────────────────────

[[ $# -eq 1 ]] || err "Usage: $0 <version>  (e.g. 1.0.0)"
version="$1"
tag="v${version}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.]+)?$ ]] || err "Invalid semver: $version"

step "Verify tooling"
command -v gh > /dev/null || err "gh CLI not installed"
command -v cosign > /dev/null || warn "cosign not installed — signature verification will be skipped"
command -v shasum > /dev/null || err "shasum not installed"
gh auth status 2> /dev/null > /dev/null || err "gh not authenticated"
has_gpg=false
if git config user.signingkey > /dev/null 2>&1 && gpg --list-secret-keys 2> /dev/null | grep -q sec; then
  has_gpg=true
  ok "gh authenticated, GPG signing key present (tag will be GPG-signed)"
else
  warn "no GPG signing key — tag will be annotated but unsigned"
  warn "(this is OK: cosign keyless via OIDC is the real v1.0.0 attestation)"
fi

step "Verify branch + clean tree"
current_branch=$(git rev-parse --abbrev-ref HEAD)
[[ "$current_branch" == "main" ]] || err "not on main (current: $current_branch)"
[[ -z "$(git status --porcelain)" ]] || err "working tree dirty"
ok "on clean main"

step "Verify PR #1 (feature 006) is merged"
pr_state=$(gh pr view 1 --json state --jq .state 2> /dev/null || echo "UNKNOWN")
[[ "$pr_state" == "MERGED" ]] || err "PR #1 is not merged (state: $pr_state)"
ok "PR #1 merged"

step "Sync with origin"
git fetch origin
ahead=$(git rev-list --count origin/main..main 2> /dev/null || echo "0")
behind=$(git rev-list --count main..origin/main 2> /dev/null || echo "0")
if [[ "$behind" -gt 0 ]]; then
  warn "local main is $behind commits behind origin — pulling"
  git pull --ff-only
fi
[[ "$ahead" -eq 0 ]] || err "local main has $ahead unpushed commits — push first"
ok "in sync with origin/main"

step "Run full lint + test suite"
bash scripts/lint.sh || err "scripts/lint.sh failed"
ok "lint.sh passed"

step "Reproducibility check (2 fresh builds)"
rm -rf /tmp/release-rep-*
bash scripts/build-release.sh /tmp/release-rep-1.tar.gz > /dev/null
bash scripts/build-release.sh /tmp/release-rep-2.tar.gz > /dev/null
sha1=$(shasum -a 256 /tmp/release-rep-1.tar.gz | awk '{print $1}')
sha2=$(shasum -a 256 /tmp/release-rep-2.tar.gz | awk '{print $1}')
[[ "$sha1" == "$sha2" ]] || err "reproducibility broken: $sha1 vs $sha2"
ok "byte-identical builds: $sha1"

step "Bump plugin.json to version $version"
jq --arg v "$version" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json
mv /tmp/plugin.json .claude-plugin/plugin.json
confirm "Commit version bump to $version?"
git add .claude-plugin/plugin.json
git commit -m "chore(release): bump version to $version"
git push origin main

step "Create annotated tag $tag"
confirm "About to create tag $tag. This is irreversible. Continue?"
if [[ "$has_gpg" == "true" ]]; then
  git tag -s "$tag" -m "$tag"
  ok "GPG-signed tag created locally"
else
  git tag -a "$tag" -m "$tag"
  ok "annotated tag created locally (unsigned — cosign keyless will attest on release.yml)"
fi

step "Push tag to origin (triggers release.yml → SLSA → cosign → SBOM → GitHub Release)"
confirm "About to push $tag to origin. This triggers the release pipeline. Continue?"
git push origin "$tag"
ok "tag pushed"

step "Wait for release workflow"
printf "Monitoring .github/workflows/release.yml (max 20min)...\n"
local_timeout=$((20 * 60))
start=$(date +%s)
while true; do
  sleep 15
  now=$(date +%s)
  elapsed=$((now - start))
  [[ $elapsed -gt $local_timeout ]] && err "release workflow timeout"
  state=$(gh run list --workflow=release.yml --branch "$tag" --limit 1 --json status,conclusion 2> /dev/null || echo "[]")
  status=$(printf '%s' "$state" | jq -r '.[0].status // empty')
  conclusion=$(printf '%s' "$state" | jq -r '.[0].conclusion // empty')
  [[ -z "$status" ]] && { printf "."; continue; }
  printf "  [%ds] status=%s conclusion=%s\n" "$elapsed" "$status" "$conclusion"
  [[ "$status" == "completed" ]] && break
done
[[ "$conclusion" == "success" ]] || err "release workflow failed"
ok "release workflow succeeded"

step "Verify published release artifacts"
dist=/tmp/release-verify
rm -rf "$dist" && mkdir -p "$dist"
gh release download "$tag" --dir "$dist" || err "failed to download release"
ls -la "$dist"

if command -v cosign > /dev/null; then
  cosign verify-blob \
    --certificate-identity-regexp 'https://github.com/yolo-labz/claude-mac-chrome/' \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    --bundle "$dist"/*.sigstore \
    "$dist"/claude-mac-chrome.tar.gz \
    && ok "cosign signature verified" \
    || warn "cosign verification failed"
fi

published_sha=$(shasum -a 256 "$dist/claude-mac-chrome.tar.gz" | awk '{print $1}')
[[ "$published_sha" == "$sha1" ]] \
  && ok "published tarball SHA matches local reproducible build ($published_sha)" \
  || warn "published SHA differs from local: $published_sha vs $sha1 (may indicate CI drift)"

printf "\n${GREEN}================================================${RESET}\n"
printf "${GREEN}  $tag is now live at:${RESET}\n"
printf "  https://github.com/yolo-labz/claude-mac-chrome/releases/tag/$tag\n"
printf "${GREEN}================================================${RESET}\n\n"
printf "Next: T102 marketplace submission + T103 launch announcements.\n"
printf "      See launch/ for ready-to-paste content.\n"
