// Per-test harness stubs for happy-dom fidelity gaps.
// Per spec §NFR-V2-SAFETY-1..3 + HAPPY-DOM-FIDELITY.md.
//
// Happy-dom diverges from real Chrome on 3 critical DOM APIs:
//   1. getBoundingClientRect  — always returns {0,0,0,0} (GH #1416)
//   2. offsetParent/Width/Height  — same layout-engine gap
//   3. getComputedStyle(el, pseudoElt)  — ignores pseudoElt arg (GH #1773)
//
// Plus 1 integration-only API:
//   4. elementFromPoint — no layout/hit-testing at all
//
// This module installs stubs that read from `<fixture>.fixture.json`
// sidecar files so fixture authors can declare layout facts directly.
// Playwright integration tests provide authoritative verification.

import { readFileSync, existsSync } from "node:fs";

/**
 * Load the sidecar `.fixture.json` for a fixture HTML path, if it exists.
 */
export function loadFixtureSidecar(fixtureHtmlPath) {
  const sidecarPath = fixtureHtmlPath.replace(/\.html$/, ".fixture.json");
  if (!existsSync(sidecarPath)) return {};
  try {
    return JSON.parse(readFileSync(sidecarPath, "utf8"));
  } catch (e) {
    throw new Error(`Malformed fixture sidecar ${sidecarPath}: ${e.message}`);
  }
}

/**
 * Install harness stubs on a happy-dom window. Call in beforeEach AFTER
 * setting document.body content but BEFORE invoking the safety check JS.
 */
export function installStubs(window, sidecar) {
  const doc = window.document;
  const Element = window.Element;

  // Stub 1: getBoundingClientRect. Returns {0,0,0,0} in happy-dom by
  // default, so anything that falls through to the fallback gets caught
  // by the zero_dimensions rail. Sidecar can declare non-zero rects for
  // positive cases.
  const rects = (sidecar && sidecar.rects) || {};
  const originalGBCR = Element.prototype.getBoundingClientRect;
  Element.prototype.getBoundingClientRect = function () {
    // Match by id first (most common), then by selector walk
    if (this.id && rects[`#${this.id}`]) {
      const r = rects[`#${this.id}`];
      return {
        x: r.x ?? r.left ?? 0,
        y: r.y ?? r.top ?? 0,
        width: r.width ?? 0,
        height: r.height ?? 0,
        top: r.top ?? r.y ?? 0,
        left: r.left ?? r.x ?? 0,
        right: r.right ?? (r.x ?? 0) + (r.width ?? 0),
        bottom: r.bottom ?? (r.y ?? 0) + (r.height ?? 0),
      };
    }
    // No sidecar entry: fall through to happy-dom's 0,0,0,0 default,
    // which is explicitly correct for the zero_dimensions fixture.
    return originalGBCR.call(this);
  };

  // Stub 2: getComputedStyle pseudo-element support. Happy-dom ignores
  // the pseudoElt arg entirely, so CSS `::before { content: "..." }`
  // label detection is invisible. Read from sidecar `pseudo_elements`.
  const pseudoMap = (sidecar && sidecar.pseudo_elements) || {};
  const originalGCS = window.getComputedStyle.bind(window);
  window.getComputedStyle = function (el, pseudoElt) {
    const baseStyle = originalGCS(el, pseudoElt);
    if (!pseudoElt) return baseStyle;

    // Build a selector key for this element
    const selectorKey = el.id ? `#${el.id}` : null;
    if (selectorKey && pseudoMap[selectorKey] && pseudoMap[selectorKey][pseudoElt]) {
      const pseudoDecl = pseudoMap[selectorKey][pseudoElt];
      return new Proxy(baseStyle, {
        get(target, prop) {
          if (prop === "content" && pseudoDecl.content !== undefined) {
            return pseudoDecl.content;
          }
          return target[prop];
        },
      });
    }
    return baseStyle;
  };

  // Stub 3: elementFromPoint (hit-testing). Happy-dom has no layout;
  // returns null or document.body. Read sidecar `hit_test` map.
  const hitTestMap = (sidecar && sidecar.hit_test) || {};
  doc.elementFromPoint = function (x, y) {
    const key = `${Math.round(x)},${Math.round(y)}`;
    const sel = hitTestMap[key];
    if (sel) return doc.querySelector(sel);
    return null;
  };
}
