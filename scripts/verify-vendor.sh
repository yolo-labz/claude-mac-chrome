#!/usr/bin/env bash
# Feature 006 T011 — Vendor re-verification script.
# Per spec §NFR-V2-VEND-3..5.
#
# Re-derives tests/vendor/happy-dom.mjs from upstream in a clean temp
# dir using the reproducer command from VENDOR-MANIFEST.json, then
# byte-compares against the committed file. Non-zero exit on mismatch.
#
# This is the authoritative defense against silent supply-chain drift.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/tests/VENDOR-MANIFEST.json"
COMMITTED="$REPO_ROOT/tests/vendor/happy-dom.mjs"

if [[ ! -f "$MANIFEST" ]]; then
  echo "FATAL: $MANIFEST not found"
  exit 1
fi

if [[ ! -f "$COMMITTED" ]]; then
  echo "FATAL: $COMMITTED not present. Run initial vendor-bundle ceremony."
  exit 1
fi

# Extract pinned values from manifest
version=$(jq -r .upstream_version "$MANIFEST")
commit=$(jq -r .upstream_commit "$MANIFEST")
expected_bundle_sha=$(jq -r .bundle_sha256 "$MANIFEST")
expected_tarball_sha=$(jq -r .upstream_tarball_sha256 "$MANIFEST")

if [[ "$version" == "UNSET" || "$commit" == "UNSET" || "$expected_bundle_sha" == "UNSET" ]]; then
  echo "NOTE: VENDOR-MANIFEST.json still has UNSET sentinel values."
  echo "      Run the initial vendor ceremony to populate."
  exit 2
fi

# Require tools
for t in jq sha256sum shasum curl tar node npx; do
  command -v "$t" > /dev/null 2>&1 || {
    # shasum is macOS, sha256sum is Linux — either is fine
    [[ "$t" == "sha256sum" ]] && command -v shasum > /dev/null && continue
    [[ "$t" == "shasum" ]] && command -v sha256sum > /dev/null && continue
    echo "FATAL: $t not in PATH"
    exit 1
  }
done

# Pick hash tool
hash_tool() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

tmpdir=$(mktemp -d -t vendor-verify-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

echo "Fetching happy-dom @$commit from upstream..."
cd "$tmpdir"
curl -sL "https://codeload.github.com/capricorn86/happy-dom/tar.gz/$commit" -o src.tar.gz
actual_tarball_sha=$(hash_tool src.tar.gz)
if [[ "$actual_tarball_sha" != "$expected_tarball_sha" ]]; then
  echo "FATAL: upstream tarball SHA mismatch"
  echo "  expected: $expected_tarball_sha"
  echo "  actual:   $actual_tarball_sha"
  exit 1
fi

tar xzf src.tar.gz
cd "happy-dom-$commit/packages/happy-dom"

echo "Building deterministic bundle..."
npm ci --ignore-scripts 2>/dev/null || npm install --ignore-scripts --silent
SOURCE_DATE_EPOCH=1700000000 \
  ./node_modules/.bin/esbuild --bundle src/index.ts \
  --format=esm \
  --platform=neutral \
  --target=es2022 \
  --minify=false \
  --outfile="$tmpdir/rebuilt.mjs"

actual_bundle_sha=$(hash_tool "$tmpdir/rebuilt.mjs")
if [[ "$actual_bundle_sha" != "$expected_bundle_sha" ]]; then
  echo "FATAL: rebuilt bundle SHA mismatch"
  echo "  expected (manifest): $expected_bundle_sha"
  echo "  actual  (rebuilt):   $actual_bundle_sha"
  exit 1
fi

# Byte-compare against committed file
if ! cmp -s "$tmpdir/rebuilt.mjs" "$COMMITTED"; then
  echo "FATAL: committed tests/vendor/happy-dom.mjs differs from reproduced build"
  diff "$tmpdir/rebuilt.mjs" "$COMMITTED" | head -40
  exit 1
fi

echo "PASS: vendored happy-dom is byte-identical to upstream reproduction"
