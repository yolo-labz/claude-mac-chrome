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

# ClusterFuzzLite's OSS-Fuzz-derived contract requires a `compile`
# executable on $PATH inside the container. Wire build.sh in as that
# entry point so `Build fuzzers` finds it (#48). build.sh generates
# the fuzz_* wrappers into $OUT at compile time — pre-staging them
# here under /out is pointless because CFL invokes the build container
# with `--volumes-from <helper>` against a helper that declares /out
# as a volume, which shadows any image-baked /out content with an
# empty volume mount (#50).
COPY .clusterfuzzlite/build.sh /usr/local/bin/compile
RUN chmod +x /usr/local/bin/compile
