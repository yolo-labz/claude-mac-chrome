#!/usr/bin/env node
// PR #22 — TOCTOU drift probe.
// Loads happy-dom + the emitted safety JS, snapshots the element
// fingerprint, mutates the DOM, then runs the dispatch JS with the
// stale fingerprint injected and verifies toctou_drift is caught.
//
// Exit 0 on success. Exit 1 on any contract violation. Exit 77 when
// happy-dom vendor bundle is missing (CI treats as skip).

import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { installStubs } from "./harness-stubs.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const LIB = join(REPO_ROOT, "skills", "chrome-multi-profile", "chrome-lib.sh");
const VENDOR = join(REPO_ROOT, "tests", "vendor", "happy-dom.mjs");

if (!existsSync(VENDOR)) {
  console.error("happy-dom vendor missing; skipping");
  process.exit(77);
}
const { Window } = await import(VENDOR);

function emitSafety() {
  const r = spawnSync("bash", [LIB, "_emit_safety_js", "#target"]);
  if (r.status !== 0) throw new Error("safety emit failed: " + r.stderr);
  return r.stdout.toString();
}

const SAFETY_JS = emitSafety();

function mkWindow() {
  const win = new Window({ url: "https://example.com/", innerWidth: 1024, innerHeight: 768 });
  const btn = win.document.createElement("button");
  btn.id = "target";
  btn.textContent = "Mark as read";
  win.document.body.appendChild(btn);
  installStubs(win, { rects: { "#target": { x: 100, y: 100, width: 120, height: 40 } } });
  return win;
}

function runSafety(win) {
  const fn = new win.Function(`return ${SAFETY_JS.trim()}`);
  return fn();
}

function runDispatch(win, expectedFp) {
  const selJson = JSON.stringify("#target");
  const expJson = JSON.stringify(expectedFp);
  const js = `return (function(){
    try {
      const _QS = document.querySelector.bind(document);
      const _EXPECTED_FP = ${expJson};
      function _fnv1a(s){let h=0x811c9dc5;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=(h+((h<<1)+(h<<4)+(h<<7)+(h<<8)+(h<<24)))>>>0;}return h.toString(16);}
      const el = _QS(${selJson});
      if (!el) return JSON.stringify({ok:false,error:"element_vanished"});
      const rect = el.getBoundingClientRect();
      if (_EXPECTED_FP) {
        const _cur_fp = {
          tag: el.tagName || "",
          id: el.id || "",
          outerHTML_hash: _fnv1a((el.outerHTML || "").slice(0, 5000)),
          rect: {x: Math.round(rect.left), y: Math.round(rect.top),
                 w: Math.round(rect.width), h: Math.round(rect.height)}
        };
        const drift = [];
        if (_cur_fp.tag !== _EXPECTED_FP.tag) drift.push("tag");
        if (_cur_fp.id !== _EXPECTED_FP.id) drift.push("id");
        if (_cur_fp.outerHTML_hash !== _EXPECTED_FP.outerHTML_hash) drift.push("outerHTML_hash");
        const er = _EXPECTED_FP.rect || {x:0,y:0,w:0,h:0};
        if (Math.abs(_cur_fp.rect.x - er.x) > 4 || Math.abs(_cur_fp.rect.y - er.y) > 4 ||
            Math.abs(_cur_fp.rect.w - er.w) > 4 || Math.abs(_cur_fp.rect.h - er.h) > 4) {
          drift.push("rect");
        }
        if (drift.length > 0) return JSON.stringify({ok:false, error:"toctou_drift", drift:drift, current: _cur_fp});
      }
      return JSON.stringify({ok:true});
    } catch(e){
      return JSON.stringify({ok:false, error:"dispatch_exception", msg:String(e)});
    }
  })();`;
  const fn = new win.Function(js);
  return fn();
}

function assert(cond, msg) {
  if (!cond) {
    console.error("ASSERT FAIL:", msg);
    process.exit(1);
  }
}

// --- Case 1: stable DOM — no drift --------------------------------------
{
  const win = mkWindow();
  const safetyJson = runSafety(win);
  const safety = JSON.parse(safetyJson);
  assert(safety.ok === true, "safety must pass for baseline: got " + safetyJson);
  assert(safety.element_fingerprint, "fingerprint must be present in envelope");
  const fp = safety.element_fingerprint;
  assert(typeof fp.outerHTML_hash === "string" && fp.outerHTML_hash.length > 0, "outerHTML_hash present");
  assert(fp.tag === "BUTTON", "tag=BUTTON, got " + fp.tag);
  assert(fp.id === "target", "id=target, got " + fp.id);

  const dispatch = JSON.parse(runDispatch(win, fp));
  assert(dispatch.ok === true, "stable DOM must not drift: " + JSON.stringify(dispatch));
  console.log("PASS case 1: stable DOM, no drift");
}

// --- Case 2: outerHTML mutated between snapshot and dispatch ------------
{
  const win = mkWindow();
  const safety = JSON.parse(runSafety(win));
  const fp = safety.element_fingerprint;
  win.document.querySelector("#target").textContent = "Buy now";
  const dispatch = JSON.parse(runDispatch(win, fp));
  assert(dispatch.ok === false && dispatch.error === "toctou_drift",
    "text mutation must trigger drift: " + JSON.stringify(dispatch));
  assert(dispatch.drift.includes("outerHTML_hash"), "drift must name outerHTML_hash");
  console.log("PASS case 2: outerHTML mutation caught");
}

// --- Case 3: attacker rewrites button content mid-flight ----------------
{
  const win = mkWindow();
  const safety = JSON.parse(runSafety(win));
  const fp = safety.element_fingerprint;
  const btn = win.document.querySelector("#target");
  btn.setAttribute("data-old", "1");
  btn.textContent = "Pay $999";
  const dispatch = JSON.parse(runDispatch(win, fp));
  assert(dispatch.ok === false && dispatch.error === "toctou_drift",
    "attacker mutation must trigger drift: " + JSON.stringify(dispatch));
  console.log("PASS case 3: attacker repoint caught");
}

// --- Case 4: null expected_fp → no drift check (back-compat) ------------
{
  const win = mkWindow();
  const dispatch = JSON.parse(runDispatch(win, null));
  assert(dispatch.ok === true, "null expected_fp must skip drift check");
  console.log("PASS case 4: null fingerprint bypass (back-compat)");
}

console.log("\nALL PASSED");
