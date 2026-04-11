// Feature 006 T051 — pseudo-element content integration test.
// Per spec §NFR-V2-SAFETY-3.
//
// Happy-dom ignores the pseudoElt argument to getComputedStyle entirely
// (GH #1773), so CSS `::before { content: "Subscribe" }` label detection
// is impossible to verify there. Real Chromium is authoritative.

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

test("pseudo: ::before content 'Subscribe' caught via getComputedStyle", async ({
  page,
}) => {
  await page.goto("/05-pseudo-before-content.html");
  await page.addScriptTag({ content: emitSafetyJs("#target") });
  const envelope = await page.evaluate(() => (window as any).__cmc_envelope);
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toMatch(/^purchase_button_text_depth_/);
});
