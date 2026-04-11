# `scripts/lint.sh` Runtime Baseline

Per spec §NFR-V2-PERF-2 — the full verification suite should complete in < 10 seconds on Pedro's machine for fast PR feedback.

## Baseline (to be populated on v1.0.0 tag)

Measure with:
```bash
time bash scripts/lint.sh
```

| Stage | Expected duration | Notes |
|---|---|---|
| shfmt | < 0.5s | Single-file diff |
| shellcheck | < 1s | Style severity, 2 files |
| zero-Python heredoc check | < 0.1s | Single grep |
| forbidden-pattern check | < 0.1s | Single grep |
| safety helper presence | < 0.1s | 11 grep calls |
| HAPPY-DOM fidelity lint | < 0.3s | awk + grep |
| fixture determinism lint | < 0.2s | Recursive grep on tests/fixtures/ |
| smoke test | skipped unless Chrome running | |
| `tests/run.sh` bats | < 3s | 10 bats files, ~80 test cases |
| `tests/run.sh` js-fixtures | < 4s | 15 fixtures, happy-dom |
| `tests/run.sh` Stryker | optional | Not wired into dev loop by default |

**Target total:** < 10 seconds (excluding Stryker, excluding smoke test requiring Chrome).

## Measurement log

*(Populate on first green v1.0.0 release.)*

| Date | Commit | Duration (s) | Machine | Notes |
|---|---|---|---|---|
| TBD | TBD | TBD | Pedro's macbook-pro (aarch64-darwin) | Baseline |
