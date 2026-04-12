#!/bin/bash -eu
# ClusterFuzzLite build script. Copies fuzz targets to $OUT.
# Our targets are shell/node wrappers, not compiled libFuzzer binaries.
# The Dockerfile handles the actual build; this script satisfies the
# ClusterFuzzLite contract of having a build.sh present.

cp /out/fuzz_* "$OUT/" 2>/dev/null || true
