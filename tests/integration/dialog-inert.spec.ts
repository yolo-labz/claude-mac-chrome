// Feature 006 T052 — <dialog> showModal inert propagation test.
// Per spec §NFR-V2-SAFETY-5.
//
// Happy-dom does not implement top-layer or automatic inert-ing of
// sibling subtrees when showModal() is called. Real Chromium is
// the only place this can be verified.

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

test("dialog: button inside dialog without open attr is inert-blocked", async ({
  page,
}) => {
  await page.goto("/06-inert-ancestor.html");
  await page.addScriptTag({ content: emitSafetyJs("#target") });
  const envelope = await page.evaluate(() => (window as any).__cmc_envelope);
  expect(envelope.element_found).toBe(true);
  expect(envelope.ok).toBe(false);
  expect(envelope.blocked_reason).toBe("inert_container");
});
