FROM node:20-bookworm@sha256:8789e1e0752d81088a085689c04fdb7a5b16e8102e353118a4b049bbf05db8ac AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash jq radamsa \
  && rm -rf /var/lib/apt/lists/*

COPY . /src
WORKDIR /src

# ClusterFuzzLite expects fuzz targets as executables in /out/.
# Our fuzzers are shell + node scripts — wrap them as executable entry points.
RUN mkdir -p /out && \
    cp tests/fuzz/radamsa-urls.sh /out/fuzz_radamsa_urls && \
    chmod +x /out/fuzz_radamsa_urls && \
    printf '#!/usr/bin/env bash\nexec node /src/tests/fuzz/html-grammar.mjs --iterations="${1:-1000}"\n' > /out/fuzz_html_grammar && \
    chmod +x /out/fuzz_html_grammar && \
    printf '#!/usr/bin/env bash\nexec node /src/tests/fuzz/unicode-confusables.mjs\n' > /out/fuzz_unicode_confusables && \
    chmod +x /out/fuzz_unicode_confusables
