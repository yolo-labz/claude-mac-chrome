FROM node:20-bookworm@sha256:8789e1e0752d81088a085689c04fdb7a5b16e8102e353118a4b049bbf05db8ac AS builder

# radamsa is no longer available as a Debian/Ubuntu apt package on the
# images used by ClusterFuzzLite (and apt-get install radamsa now fails
# with "Unable to locate package" — see #45). Build radamsa from source
# at the upstream pinned tag, mirroring the .github/workflows/fuzz.yml
# pattern so the PR + cron Docker builds and the nightly host build use
# the same radamsa version.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash jq git ca-certificates build-essential \
  && git clone --depth 1 --branch v0.6 https://gitlab.com/akihe/radamsa.git /tmp/radamsa \
  && make -C /tmp/radamsa \
  && make -C /tmp/radamsa install \
  && rm -rf /tmp/radamsa /var/lib/apt/lists/* \
  && radamsa --version

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

# ClusterFuzzLite's OSS-Fuzz-derived contract requires a `compile`
# executable on $PATH inside the container. Wire build.sh in as that
# entry point so `Build fuzzers` finds it (#48).
COPY .clusterfuzzlite/build.sh /usr/local/bin/compile
RUN chmod +x /usr/local/bin/compile
