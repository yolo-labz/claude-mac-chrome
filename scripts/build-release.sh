#!/usr/bin/env bash
# Feature 006 T068 — deterministic release tarball builder.
# Per spec §NFR-V2-REPRO-1..4.
#
# Produces a byte-identical tarball suitable for cosign signing,
# SLSA L3 attestation, and reproducibility CI. Pinned gnu-tar, pinned
# SOURCE_DATE_EPOCH (from last commit time), canonicalized file order,
# zeroed owner/group, UTC mtime, no extended attributes.
#
# Usage: scripts/build-release.sh [output-path]
#   Default output: dist/claude-mac-chrome.tar.gz

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

output="${1:-dist/claude-mac-chrome.tar.gz}"
mkdir -p "$(dirname "$output")"

# --- Require GNU tar (BSD tar does not support --sort --mtime) --------

gtar_bin=""
for candidate in gtar gnutar tar; do
  if command -v "$candidate" > /dev/null 2>&1; then
    if "$candidate" --version 2>&1 | grep -q "GNU tar"; then
      gtar_bin="$candidate"
      break
    fi
  fi
done
if [[ -z "$gtar_bin" ]]; then
  echo "FATAL: GNU tar required (brew install gnu-tar)" >&2
  exit 1
fi

# --- SOURCE_DATE_EPOCH from last commit --------------------------------

if [[ -n "${SOURCE_DATE_EPOCH:-}" ]]; then
  epoch="$SOURCE_DATE_EPOCH"
else
  epoch=$(git log -1 --format=%ct HEAD)
fi
export SOURCE_DATE_EPOCH="$epoch"

# --- Guardrail: no .git/ in staging ------------------------------------

if [[ -e .git-staging ]]; then
  rm -rf .git-staging
fi
mkdir -p .git-staging
trap 'rm -rf .git-staging' EXIT

# Collect release files deterministically
git ls-files \
  -- ':!tests/integration' ':!tests/vendor' ':!tests/fuzz' ':!tests/js-fixtures' \
     ':!tests/bench' ':!tests/stryker.conf.mjs' ':!.github' ':!scripts/verify-vendor.sh' \
     ':!scripts/regenerate-goldens.sh' ':!.specify' ':!launch' \
  | while read -r f; do
    [[ -e "$f" ]] || continue
    mkdir -p ".git-staging/$(dirname "$f")"
    cp -p "$f" ".git-staging/$f"
  done

if find .git-staging -name ".git" -print -quit | grep -q .; then
  echo "FATAL: .git/ sneaked into staging area" >&2
  exit 1
fi

# --- Produce deterministic tarball -------------------------------------

"$gtar_bin" \
  --sort=name \
  --mtime="@$epoch" \
  --owner=0 --group=0 --numeric-owner \
  --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
  --format=posix \
  -C .git-staging \
  -cf - \
  . \
  | gzip -n -9 > "$output"

echo "Built: $output"
shasum -a 256 "$output"
