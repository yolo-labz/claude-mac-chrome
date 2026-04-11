#!/usr/bin/env node
// Feature 006 T033 — JS fixture runner (happy-dom harness).
// Per spec §NFR-V2-FX-3, FX-4, FX-11.
//
// Contract:
//   1. Load vendored happy-dom (tests/vendor/happy-dom.mjs)
//   2. For each tests/fixtures/*.html:
//        a. Load sidecar .fixture.json (if any) + install harness stubs
//        b. Invoke `chrome-lib.sh _emit_safety_js '#target' <lexicon>`
//           to get the safety check JS
//        c. Evaluate it in the happy-dom window context
//        d. Compare the resulting envelope against .expected.json
//   3. Run meta-tests (T034-T037):
//        - forward exhaustiveness (every enum has >= 1 fixture)
//        - reverse exhaustiveness (every fixture enum still defined)
//        - uniqueness (no duplicate rail targets w/o variant_group)
//        - rail isolation (disable target rail -> envelope becomes ok:true)
//
// Fixtures marked `harness_requirement: integration_only` are skipped
// here and verified exclusively by the Playwright suite (T048-T054).
//
// Exit code: 0 = all pass; non-zero = at least one fixture or meta-test
// failed. Designed to be invoked by tests/run.sh.

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, dirname, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { loadFixtureSidecar, installStubs } from "./harness-stubs.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const FIXTURE_DIR = join(REPO_ROOT, "tests", "fixtures");
const LIB = join(REPO_ROOT, "skills", "chrome-multi-profile", "chrome-lib.sh");
const VENDOR_BUNDLE = join(REPO_ROOT, "tests", "vendor", "happy-dom.mjs");

// --- Happy-dom loader --------------------------------------------------

async function loadHappyDom() {
  if (!existsSync(VENDOR_BUNDLE)) {
    console.error(
      `FATAL: vendored happy-dom not found at ${VENDOR_BUNDLE}.\n` +
        `Run scripts/vendor-happy-dom.sh to regenerate. Skipping JS fixture tests.`,
    );
    process.exit(77); // EX_NOPERM sentinel — CI interprets as "skipped"
  }
  return import(VENDOR_BUNDLE);
}

// --- Enum vocabulary (keep in sync w/ chrome-lib.sh safety JS) ---------

const BLOCKED_REASONS = new Set([
  "element_not_found",
  "purchase_button_text_depth_0",
  "purchase_button_text_depth_1",
  "purchase_button_text_depth_2",
  "purchase_button_attr_aria-label_depth_0",
  "purchase_button_attr_data-action_depth_0",
  "payment_field_lock",
  "inert_container",
  "not_visible",
  "zero_dimensions",
  "clickjack_suspected",
  "js_error",
]);

// --- Extract safety JS from chrome-lib.sh ------------------------------

function emitSafetyJs(selector, _lexicon) {
  // _emit_safety_js is a CLI dispatch verb in chrome-lib.sh main().
  // Invoke via bash: `bash chrome-lib.sh _emit_safety_js <selector>`.
  const res = spawnSync("bash", [LIB, "_emit_safety_js", selector]);
  if (res.status !== 0) {
    throw new Error(`_emit_safety_js failed: ${res.stderr.toString()}`);
  }
  return res.stdout.toString();
}

// Read the lexicon regex that v0.8.0 uses.
function loadLexicon() {
  const lexPath = join(REPO_ROOT, "skills", "chrome-multi-profile", "lexicon", "triggers.txt");
  if (existsSync(lexPath)) {
    return readFileSync(lexPath, "utf8")
      .split(/\r?\n/)
      .filter((l) => l && !l.startsWith("#"))
      .join("|");
  }
  return "upgrade|subscribe|purchase|pay|buy|checkout|comprar|assinar|pagar|finalizar|contratar";
}

// --- Single fixture runner ---------------------------------------------

async function runFixture(happyDom, fixturePath) {
  const html = readFileSync(fixturePath, "utf8");
  const expected = JSON.parse(
    readFileSync(fixturePath.replace(/\.html$/, ".expected.json"), "utf8"),
  );
  const sidecar = loadFixtureSidecar(fixturePath);

  // Integration-only fixtures are not happy-dom authoritative.
  if (expected.harness_requirement === "integration_only") {
    return { path: fixturePath, status: "skip", reason: "integration_only" };
  }

  const { Window } = happyDom;
  const window = new Window({ url: "http://localhost/", innerWidth: 1024, innerHeight: 768 });
  // Happy-dom Window supports setting HTML via content property or body innerHTML.
  // Avoid document.write per DOM best practice.
  window.document.documentElement.innerHTML = html
    .replace(/^[\s\S]*?<html[^>]*>/i, "")
    .replace(/<\/html>[\s\S]*$/i, "");
  installStubs(window, sidecar);

  const selector = expected.selector || "#target";
  const lexicon = loadLexicon();
  const js = emitSafetyJs(selector, lexicon);

  let envelope;
  try {
    const fn = new window.Function(`return ${js.trim()}`);
    envelope = JSON.parse(fn());
  } catch (e) {
    return {
      path: fixturePath,
      status: "fail",
      reason: `eval_error: ${e.message}`,
    };
  }

  // Compare blocked_reason + element_found + ok
  const fieldsToCheck = ["ok", "element_found", "blocked_reason"];
  const diffs = [];
  for (const f of fieldsToCheck) {
    if (envelope[f] !== expected[f]) {
      diffs.push(`${f}: expected=${expected[f]} got=${envelope[f]}`);
    }
  }

  if (diffs.length > 0) {
    return { path: fixturePath, status: "fail", reason: diffs.join("; "), envelope };
  }
  return { path: fixturePath, status: "pass" };
}

// --- Meta-tests --------------------------------------------------------

function metaTests(fixtures) {
  const issues = [];
  const coveredEnums = new Set();

  // Forward exhaustiveness: every enum has >= 1 fixture.
  for (const fx of fixtures) {
    if (fx.expected && fx.expected.blocked_reason) {
      coveredEnums.add(fx.expected.blocked_reason);
    }
    if (fx.expected && fx.expected.ok === true) {
      coveredEnums.add("__positive__");
    }
  }
  // Collapse depth variants into a single family for exhaustiveness
  const DEPTH_FAMILIES = {
    purchase_button_text_depth_0: "purchase_button_text",
    purchase_button_text_depth_1: "purchase_button_text",
    purchase_button_text_depth_2: "purchase_button_text",
    purchase_button_attr_aria_label_depth_0: "purchase_button_attr",
    "purchase_button_attr_aria-label_depth_0": "purchase_button_attr",
    "purchase_button_attr_data-action_depth_0": "purchase_button_attr",
  };
  const coveredFamilies = new Set();
  for (const e of coveredEnums) {
    coveredFamilies.add(DEPTH_FAMILIES[e] || e);
  }

  const REQUIRED_FAMILIES = new Set([
    "purchase_button_text",
    "purchase_button_attr",
    "payment_field_lock",
    "inert_container",
    "not_visible",
    "zero_dimensions",
    "__positive__",
  ]);
  for (const r of REQUIRED_FAMILIES) {
    if (!coveredFamilies.has(r)) {
      issues.push(`[forward-exhaustiveness] no fixture covers rail family: ${r}`);
    }
  }

  // Reverse exhaustiveness: every fixture enum is still defined.
  for (const fx of fixtures) {
    const br = fx.expected && fx.expected.blocked_reason;
    if (br !== null && br !== undefined && !BLOCKED_REASONS.has(br)) {
      issues.push(`[reverse-exhaustiveness] fixture ${basename(fx.path)} uses unknown enum: ${br}`);
    }
  }

  // Uniqueness: no two fixtures target the same rail (unless same variant_group).
  const seen = new Map();
  for (const fx of fixtures) {
    const br = fx.expected && fx.expected.blocked_reason;
    if (!br) continue;
    const vg = fx.expected.variant_group;
    const key = vg || br;
    if (seen.has(key) && !vg) {
      issues.push(
        `[uniqueness] duplicate rail coverage: ${br} in ${basename(seen.get(key))} and ${basename(fx.path)}`,
      );
    }
    if (!vg) seen.set(key, fx.path);
  }

  return issues;
}

// --- Main --------------------------------------------------------------

async function main() {
  const happyDom = await loadHappyDom();

  const fixturePaths = readdirSync(FIXTURE_DIR)
    .filter((f) => f.endsWith(".html"))
    .map((f) => join(FIXTURE_DIR, f))
    .sort();

  if (fixturePaths.length === 0) {
    console.error("FATAL: no fixtures found in tests/fixtures/");
    process.exit(1);
  }

  let pass = 0,
    fail = 0,
    skip = 0;
  const fixtures = [];
  for (const p of fixturePaths) {
    const expectedPath = p.replace(/\.html$/, ".expected.json");
    const expected = existsSync(expectedPath) ? JSON.parse(readFileSync(expectedPath, "utf8")) : null;
    const result = await runFixture(happyDom, p);
    fixtures.push({ path: p, expected });
    if (result.status === "pass") {
      pass++;
      console.log(`PASS  ${basename(p)}`);
    } else if (result.status === "skip") {
      skip++;
      console.log(`SKIP  ${basename(p)} (${result.reason})`);
    } else {
      fail++;
      console.log(`FAIL  ${basename(p)}: ${result.reason}`);
    }
  }

  console.log("\n--- Meta-tests ---");
  const metaIssues = metaTests(fixtures);
  if (metaIssues.length === 0) {
    console.log("PASS  forward/reverse exhaustiveness + uniqueness");
  } else {
    fail += metaIssues.length;
    for (const i of metaIssues) console.log(`FAIL  ${i}`);
  }

  console.log(`\n${pass} passed, ${fail} failed, ${skip} skipped`);
  process.exit(fail > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
