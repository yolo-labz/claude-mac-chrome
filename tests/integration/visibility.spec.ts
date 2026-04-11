// Feature 006 T050 — visibility integration test.
// Per spec §NFR-V2-SAFETY-2.

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
  return page.evaluate(() => (window as any).__cmc_envelope);
}

test("visibility: zero-dimensions button blocked", async ({ page }) => {
  await page.goto("/08-zero-dimensions.html");
  const envelope = await runSafetyCheck(page, "#target");
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toBe("zero_dimensions");
});

test("visibility: hidden visibility button blocked", async ({ page }) => {
  await page.goto("/09-hidden-visibility.html");
  const envelope = await runSafetyCheck(page, "#target");
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toBe("not_visible");
});
