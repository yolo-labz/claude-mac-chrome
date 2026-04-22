#!/usr/bin/env node
// PR #20 — standalone probe for the _foldConfusables helper embedded in the
// safety check JS emitted by `chrome-lib.sh _emit_safety_js`.
//
// Usage: confusables-fold-probe.mjs <input>
//   LIB env var overrides chrome-lib.sh path.
//   Prints the folded form of <input> to stdout. Exits 0 on success.

import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const LIB = process.env.LIB || resolve(__dirname, "..", "..", "skills", "chrome-multi-profile", "chrome-lib.sh");

const input = process.argv[2];
if (input === undefined) {
  console.error("usage: confusables-fold-probe.mjs <input>");
  process.exit(2);
}

const res = spawnSync("bash", [LIB, "_emit_safety_js", ".probe"], { encoding: "utf8" });
if (res.status !== 0) {
  console.error(res.stderr);
  process.exit(3);
}

// Extract the _CONFUSABLES_FOLD object literal. The map uses only JSON-safe
// constructs ("\uXXXX" escapes + plain string values + no trailing commas),
// so JSON.parse is sufficient — no eval / Function constructor needed.
const js = res.stdout;
const m = js.match(/_CONFUSABLES_FOLD\s*=\s*(\{[\s\S]+?\});/);
if (!m) {
  console.error("fold map not found in emitted safety JS");
  process.exit(4);
}

let map;
try {
  map = JSON.parse(m[1]);
} catch (e) {
  console.error("fold map is not valid JSON:", e.message);
  console.error("first 200 chars:", m[1].slice(0, 200));
  process.exit(5);
}

function fold(s) {
  if (!s) return "";
  try { s = s.normalize("NFKD"); } catch (_) {}
  s = s.replace(/[\u0300-\u036F\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]/g, "");
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c.charCodeAt(0) < 0x80) { out += c; continue; }
    out += map[c] || c;
  }
  return out;
}

process.stdout.write(fold(input));
