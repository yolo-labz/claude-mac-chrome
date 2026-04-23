#!/usr/bin/env node
// PR #23 — verify the chrome_js_async title-sentinel wrapper under happy-dom.
// Exercises: sync-return user JS, async/Promise user JS, rejection path,
// thrown exception path, and title-restoration behaviour.
// Exit 0 on success, 1 on contract violation, 77 when happy-dom missing.

import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, "..", "..");
const LIB = join(REPO_ROOT, "skills", "chrome-multi-profile", "chrome-lib.sh");
const VENDOR = join(REPO_ROOT, "tests", "vendor", "happy-dom.mjs");

if (!existsSync(VENDOR)) {
  console.error("happy-dom vendor missing; skipping");
  process.exit(77);
}
const { Window } = await import(VENDOR);

function emitWrapper(sentinel, userJs) {
  const r = spawnSync("bash", [LIB, "_emit_js_async_wrapper", sentinel, userJs]);
  if (r.status !== 0) throw new Error("wrapper emit failed: " + r.stderr);
  return r.stdout.toString();
}

function mkWindow(initialTitle) {
  const win = new Window({ url: "https://example.com/" });
  win.document.title = initialTitle;
  return win;
}

async function runCase(name, opts) {
  const sentinel = opts.sentinel || "sent_" + Math.random().toString(16).slice(2);
  const win = mkWindow(opts.initialTitle || "OriginalTitle");
  const wrapper = emitWrapper(sentinel, opts.userJs);
  const fn = new win.Function(wrapper.trim());
  fn();
  // Wait for microtask to resolve (we're single-threaded here, so 100ms is plenty).
  await new Promise((r) => setTimeout(r, 100));
  const title = win.document.title;
  if (!title.startsWith(sentinel + ":")) {
    console.error(`FAIL ${name}: title does not start with sentinel. title=${title}`);
    process.exit(1);
  }
  const payload = JSON.parse(title.slice(sentinel.length + 1));
  opts.assert(payload, win);
  console.log(`PASS ${name}`);
}

await runCase("sync return", {
  userJs: "return 42;",
  assert: (p) => {
    if (p.ok !== true || p.value !== 42) {
      console.error("unexpected payload:", p); process.exit(1);
    }
  }
});

await runCase("async Promise resolving to string", {
  userJs: "return Promise.resolve('hello');",
  assert: (p) => {
    if (p.ok !== true || p.value !== "hello") {
      console.error("unexpected payload:", p); process.exit(1);
    }
  }
});

await runCase("Promise.reject", {
  userJs: "return Promise.reject(new Error('boom'));",
  assert: (p) => {
    if (p.ok !== false || !String(p.error).includes("boom")) {
      console.error("unexpected payload:", p); process.exit(1);
    }
  }
});

await runCase("synchronous throw inside user JS", {
  userJs: "throw new Error('sync_fail');",
  assert: (p) => {
    if (p.ok !== false || !String(p.error).includes("sync_fail")) {
      console.error("unexpected payload:", p); process.exit(1);
    }
  }
});

await runCase("undefined return becomes null (JSON-safe)", {
  userJs: "return;",
  assert: (p) => {
    if (p.ok !== true || p.value !== null) {
      console.error("unexpected payload:", p); process.exit(1);
    }
  }
});

// original title is stashed on window so host can restore it
await runCase("original title is stashed in window var", {
  sentinel: "restore_probe",
  initialTitle: "Very Important Page",
  userJs: "return 1;",
  assert: (_p, win) => {
    const stash = win["__cmc_orig_restore_probe"];
    if (stash !== "Very Important Page") {
      console.error("expected stash='Very Important Page', got=", stash);
      process.exit(1);
    }
  }
});

console.log("\nALL PASSED");
