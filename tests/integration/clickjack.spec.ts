// Feature 006 T049 — clickjack integration test.
// Per spec §NFR-V2-SAFETY-1.
//
// This layer CANNOT be tested in happy-dom (no layout engine -> no
// elementFromPoint). Real Chromium is authoritative.
//
// We inject the safety check JS as a <script> tag that writes the
// envelope into window.__cmc_envelope, then read the global back.
// This avoids any runtime eval/Function construction in test code.

import { test, expect } from "@playwright/test";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const LIB = join(REPO_ROOT, "skills", "chrome-multi-profile", "chrome-lib.sh");

function emitSafetyJs(selector: string): string {
  // The emitted JS is a trusted IIFE from our own chrome-lib.sh.
  const raw = execFileSync("bash", [LIB, "_emit_safety_js", selector], {
    encoding: "utf8",
  });
  return `window.__cmc_envelope = ${raw.trim()};`;
}

async function runSafetyCheck(page: any, selector: string): Promise<any> {
  const content = emitSafetyJs(selector);
  await page.addScriptTag({ content });
  const envelope = await page.evaluate(() => (window as any).__cmc_envelope);
  return typeof envelope === "string" ? JSON.parse(envelope) : envelope;
}

test("clickjack: overlay intercepts target -> safety check blocks", async ({
  page,
}) => {
  await page.goto("/07-clickjack-overlay.html");
  const parsed = await runSafetyCheck(page, "#target");
  expect(parsed.element_found).toBe(true);
  expect(parsed.ok).toBe(false);
});
