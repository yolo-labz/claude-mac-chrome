// Feature 006 — shadow-DOM integration test.
// Per spec §NFR-SR-V2-7 (gatherAllText must descend open shadow roots).
//
// These fixtures build their shadow DOM from an inline <script>. The
// happy-dom JS-fixture harness sets documentElement.innerHTML, which per the
// HTML spec does not execute scripts, so it can never materialize the shadow
// tree — the fixtures are marked `harness_requirement: integration_only` and
// are authoritative ONLY here, under real Chromium.
//
// We assert the purchase_button_text *family* fires rather than a fixed depth:
// the exact ancestor depth at which the token surfaces is a Chromium DOM
// detail, and the rail's contract is "the purchase lexicon was found in the
// shadow subtree", not a specific depth.

import { test, expect } from "@playwright/test";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const LIB = join(REPO_ROOT, "skills", "chrome-multi-profile", "chrome-lib.sh");

function emitSafetyJs(selector: string): string {
  const raw = execFileSync("bash", [LIB, "_emit_safety_js", selector], {
    encoding: "utf8",
  });
  return `window.__cmc_envelope = ${raw.trim()};`;
}

async function runSafetyCheck(page: any, selector: string): Promise<any> {
  await page.addScriptTag({ content: emitSafetyJs(selector) });
  return JSON.parse(await page.evaluate(() => (window as any).__cmc_envelope));
}

test("shadow-dom: open shadow root purchase token blocked", async ({ page }) => {
  await page.goto("/04-shadow-dom-open.html");
  const envelope = await runSafetyCheck(page, "#host");
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toMatch(/^purchase_button_text_depth_\d$/);
});

test("shadow-dom: nested shadow roots purchase token blocked", async ({ page }) => {
  await page.goto("/14-nested-shadow-root.html");
  const envelope = await runSafetyCheck(page, "#outer-host");
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toMatch(/^purchase_button_text_depth_\d$/);
});
