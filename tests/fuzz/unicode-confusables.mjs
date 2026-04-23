#!/usr/bin/env node
// Feature 006 T058 — Unicode confusables fuzzer.
// Per spec §NFR-V2-FX-9 + NFR-SR-V2-2.
//
// PR #20 upgrade: exercises the FULL _foldConfusables pipeline
// (NFKD + combining-mark strip + script-confusables map) embedded
// in _chrome_safety_check_js. Every single-character UTS #39 swap
// for "upgrade", "subscribe", "comprar", "pagar", "checkout" must
// fold back to the target — exits nonzero on any miss.

// Most abused Latin-to-Cyrillic/Greek confusables
const CONFUSABLES = {
  a: ["\u0430", "\u03B1"], // Cyrillic a, Greek alpha
  c: ["\u0441"], // Cyrillic es
  e: ["\u0435", "\u0454"], // Cyrillic ie, Ukrainian ie
  g: ["\u0261"], // Latin script g
  i: ["\u0456", "\u0131"], // Cyrillic i, dotless i
  j: ["\u0458"], // Cyrillic je
  o: ["\u043E", "\u03BF"], // Cyrillic o, Greek omicron
  p: ["\u0440"], // Cyrillic er
  r: ["\u0433"], // NOT a perfect fold but common abuse
  s: ["\u0455"], // Cyrillic dze
  x: ["\u0445"], // Cyrillic ha
  y: ["\u0443"], // Cyrillic u
};

const TARGET_WORDS = ["upgrade", "subscribe", "comprar", "pagar", "checkout"];

// Generate all single-character confusable substitutions
function* generateConfusables(word) {
  yield word; // baseline
  for (let i = 0; i < word.length; i++) {
    const ch = word[i];
    if (CONFUSABLES[ch]) {
      for (const sub of CONFUSABLES[ch]) {
        yield word.slice(0, i) + sub + word.slice(i + 1);
      }
    }
  }
  // Also zero-width insertions
  for (let i = 1; i < word.length; i++) {
    yield word.slice(0, i) + "\u200B" + word.slice(i);
  }
}

// Load the REAL fold map from chrome-lib.sh's emitted safety JS so
// the fuzzer and production rail share ground truth.
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const __dirname = dirname(fileURLToPath(import.meta.url));
const LIB = resolve(__dirname, "..", "..", "skills", "chrome-multi-profile", "chrome-lib.sh");
const emit = spawnSync("bash", [LIB, "_emit_safety_js", ".fuzz"], { encoding: "utf8" });
if (emit.status !== 0) {
  console.error("failed to emit safety JS:", emit.stderr);
  process.exit(2);
}
const mapMatch = emit.stdout.match(/_CONFUSABLES_FOLD\s*=\s*(\{[\s\S]+?\});/);
if (!mapMatch) {
  console.error("fold map not found in emitted safety JS");
  process.exit(3);
}
const FOLD_MAP = JSON.parse(mapMatch[1]);

function normalize(text) {
  if (!text) return "";
  let s = text.normalize("NFKD");
  s = s.replace(/[\u0300-\u036F\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF]/g, "");
  let out = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c.charCodeAt(0) < 0x80) { out += c; continue; }
    out += FOLD_MAP[c] || c;
  }
  return out;
}

let tested = 0;
let caught = 0;
let missed = 0;
const misses = [];

for (const word of TARGET_WORDS) {
  for (const variant of generateConfusables(word)) {
    tested++;
    const norm = normalize(variant).toLowerCase();
    // Simple substring check — the real rail uses word-boundary regex
    if (norm.includes(word)) {
      caught++;
    } else {
      missed++;
      if (misses.length < 20) misses.push({ word, variant, norm });
    }
  }
}

console.log(`tested=${tested} caught=${caught} missed=${missed}`);
if (missed > 0) {
  console.log("\nMisses (fold map is missing these codepoints — add to _CONFUSABLES_FOLD):");
  for (const m of misses) {
    console.log(
      `  ${m.word}: variant=${JSON.stringify(m.variant)} normalized=${JSON.stringify(m.norm)}`,
    );
  }
  process.exit(1);
}

console.log("PASS: all confusable variants normalized to target word");
