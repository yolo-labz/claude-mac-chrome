#!/bin/bash -eux
# ClusterFuzzLite build script. Generates fuzz target wrappers into $OUT.
#
# Our fuzzers are shell + node scripts, not compiled libFuzzer binaries,
# so "compile" here means: emit thin executable wrappers in $OUT/ that
# CFL's fuzzing harness can invoke.
#
# IMPORTANT: this generation must happen here, not in the Dockerfile.
# CFL invokes the build container with `--volumes-from <helper>` and an
# `OUT=...` env that points at a host-bind path the helper provides;
# any /out/fuzz_* files baked into the image are unreachable at runtime
# (either shadowed by the helper's /out volume or simply written into
# the wrong dir relative to $OUT). build.sh runs AFTER the volume
# mount with the correct $OUT in scope, so wrappers written here
# actually persist (#50).

# Belt-and-suspenders: $OUT is provided by CFL but the directory
# itself may not pre-exist inside the build container.
mkdir -p "$OUT"

# Wrapper 1: radamsa-driven URL fuzzer (existing shell script).
cp /src/tests/fuzz/radamsa-urls.sh "$OUT/fuzz_radamsa_urls"
chmod +x "$OUT/fuzz_radamsa_urls"

# Wrapper 2: HTML grammar fuzzer (node).
cat > "$OUT/fuzz_html_grammar" <<'EOF'
#!/usr/bin/env bash
exec node /src/tests/fuzz/html-grammar.mjs --iterations="${1:-1000}"
EOF
chmod +x "$OUT/fuzz_html_grammar"

# Wrapper 3: Unicode confusables fuzzer (node).
cat > "$OUT/fuzz_unicode_confusables" <<'EOF'
#!/usr/bin/env bash
exec node /src/tests/fuzz/unicode-confusables.mjs
EOF
chmod +x "$OUT/fuzz_unicode_confusables"
