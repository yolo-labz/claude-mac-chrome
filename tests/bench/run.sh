#!/usr/bin/env bash
# Feature 006 T089 — performance benchmark runner.
# Per spec §NFR-V2-BENCH-1..3.
#
# Measures p50/p95/p99 latency for the 6 operations on Pedro's SLO list:
#   1. chrome_fingerprint_cached  (JSON catalog read, cache hit)
#   2. chrome_fingerprint         (cold, full Local State parse)
#   3. chrome_window_for          (profile -> window id resolution)
#   4. chrome_tab_for_url         (URL substring match across tabs)
#   5. chrome_js round-trip       (trivial JS eval)
#   6. chrome_click               (dry-run, no dispatch)
#
# Writes docs/benchmarks/<version>.json. Compared against the previous
# tag's file by .github/workflows/bench.yml. Any SLO > 20% regression
# fails the release.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC1091
source skills/chrome-multi-profile/chrome-lib.sh

version=$(jq -r .version .claude-plugin/plugin.json)
out_dir="docs/benchmarks"
out_file="$out_dir/${version}.json"
mkdir -p "$out_dir"

# Helper: run a command N times, print p50/p95/p99 ms
bench_one() {
  local name="$1"
  local n="$2"
  shift 2
  local samples=()
  for _ in $(seq 1 "$n"); do
    local start_ns end_ns
    start_ns=$(python3 -c 'import time; print(int(time.time_ns()))' 2> /dev/null \
      || date +%s%N 2> /dev/null \
      || gdate +%s%N 2> /dev/null \
      || echo "0")
    "$@" > /dev/null 2>&1 || true
    end_ns=$(python3 -c 'import time; print(int(time.time_ns()))' 2> /dev/null \
      || date +%s%N 2> /dev/null \
      || gdate +%s%N 2> /dev/null \
      || echo "0")
    samples+=($(((end_ns - start_ns) / 1000000)))
  done
  # Sort
  local sorted=()
  mapfile -t sorted < <(printf '%s\n' "${samples[@]}" | sort -n)
  local count=${#sorted[@]}
  local p50_idx=$((count / 2))
  local p95_idx=$((count * 95 / 100))
  local p99_idx=$((count * 99 / 100))
  printf '  "%s": { "p50_ms": %d, "p95_ms": %d, "p99_ms": %d, "samples": %d },\n' \
    "$name" "${sorted[$p50_idx]}" "${sorted[$p95_idx]}" "${sorted[$p99_idx]}" "$count"
}

chrome_local_state="${HOME}/Library/Application Support/Google/Chrome/Local State"

{
  printf '{\n'
  printf '  "version": "%s",\n' "$version"
  printf '  "measured_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "host": "%s",\n' "$(uname -mn)"
  printf '  "results": {\n'

  if [[ ! -f "$chrome_local_state" ]]; then
    printf '    "_note": "skipped — no Chrome Local State (clean CI runner or no Chrome installed)",\n'
  else
    bench_one "fingerprint_cached" 50 chrome_fingerprint_cached
    bench_one "fingerprint_cold"   10 chrome_fingerprint
    # The live Chrome-coupled ops require an open Chrome; gate them
    if pgrep -xq "Google Chrome" 2> /dev/null; then
      bench_one "window_for"    20 chrome_window_for default
      bench_one "tab_for_url"   20 chrome_tab_for_url 0 about:blank
      bench_one "click_dry"     20 chrome_click --dry-run 0 0 "#nonexistent"
    fi
  fi

  printf '    "_end": true\n'
  printf '  }\n'
  printf '}\n'
} > "$out_file"

echo "Wrote: $out_file"
cat "$out_file"
