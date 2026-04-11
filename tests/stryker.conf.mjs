// Feature 006 T055 — Stryker-js mutation testing config.
// Per spec §NFR-V2-FX-8.
//
// Kill-rate floor: 85%. Mutates the extracted safety check JS module
// (via _emit_safety_js) and runs it against the 15 fixtures.
//
// Integrated into scripts/lint.sh as a gating check (optional locally,
// mandatory in release.yml).

export default {
  packageManager: "npm",
  testRunner: "command",
  commandRunner: {
    command: "node tests/js-fixtures/run.mjs",
  },
  mutate: [
    // Stryker mutates files in-place. We stage a temp copy of the
    // safety JS produced by `_emit_safety_js '#target'` before each
    // run. See tests/stryker-setup.mjs.
    "tests/.stryker-tmp/safety-js.mjs",
  ],
  reporters: ["progress", "clear-text", "html"],
  htmlReporter: { fileName: "reports/mutation/mutation.html" },
  thresholds: {
    high: 95,
    low: 85, // ← FLOOR — CI fails below this
    break: 85,
  },
  coverageAnalysis: "perTest",
  timeoutMS: 30000,
  concurrency: 4,
};
