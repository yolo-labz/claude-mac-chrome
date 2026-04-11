# Happy-DOM Fidelity Matrix

**Purpose:** Document every DOM API the safety check JS touches, annotated with its fidelity status vs real Chrome. Per spec §NFR-V2-SAFETY-META. CI MUST fail if a new API is introduced into the safety check without a corresponding row in this matrix.

**Status values:**
- **parity** — happy-dom behavior matches real Chrome; happy-dom unit tests are authoritative
- **stubbed** — happy-dom diverges from Chrome but a per-test harness stub reads from the fixture's `.fixture.json` sidecar to match Chrome behavior; happy-dom unit tests + stub are authoritative
- **integration-only** — happy-dom cannot verify; REQUIRES Playwright + real Chromium as the authoritative verification; happy-dom tests MAY be present but NOT authoritative
- **out-of-scope** — accepted caveat; neither happy-dom nor the test harness verifies this; documented reason required

## Matrix

| API | Status | Rationale | NFR reference |
|---|---|---|---|
| `document.querySelector` | parity | Happy-dom implements standard CSS selector matching for light DOM | — |
| `document.querySelectorAll` | parity | Same as above | — |
| `Element.prototype.closest` | parity | Standard ancestor walking | — |
| `Element.prototype.getAttribute` | parity | Standard attribute read | — |
| `Element.prototype.textContent` | parity | Standard text aggregation | — |
| `Element.prototype.innerText` | parity | Standard rendered text (happy-dom approximates via textContent for non-layout contexts) | — |
| `Element.prototype.shadowRoot` | parity | Open shadow roots only; closed roots opaque to both happy-dom AND real Chrome (spec-defined) | NFR-V2-SAFETY-4 |
| `ShadowRoot.querySelector` / `querySelectorAll` | parity | Standard | — |
| `ShadowRoot.mode` | parity | `"open"` / `"closed"` string | — |
| `String.prototype.normalize("NFKC")` | parity | **V8 native, not happy-dom's concern**. Explicitly called out as accepted-parity primitive per NFR-V2-SAFETY-6. | NFR-V2-SAFETY-6 |
| `document.location.href` | parity | Standard read | — |
| `document.readyState` | parity | Standard read | — |
| `document.title` | parity | Standard read | — |
| `Element.prototype.disabled` / `aria-disabled` | parity | Standard property/attribute | — |
| `Element.prototype.isConnected` | parity | Standard property | — |
| `document.contains(el)` | parity | Standard method | — |
| `document.visibilityState` | out-of-scope | Happy-dom returns static `"visible"`. Accepted caveat: AppleScript only injects into focused tabs, so real-world `visibilityState` is always `"visible"` at injection time. If any future safety-check logic reads this as a gate, upgrade to `integration-only`. | NFR-V2-SAFETY-6 |
| `getBoundingClientRect()` | **stubbed** | **Happy-dom returns `{0,0,0,0}` for everything** (GH #1416). Visibility gate would silently pass all buttons as "invisible". Harness stub in `tests/js-fixtures/harness-stubs.mjs` reads rect from fixture's `.fixture.json` sidecar. Real-Chrome Playwright integration required as authoritative verification. | NFR-V2-SAFETY-2 |
| `Element.offsetParent` / `offsetWidth` / `offsetHeight` | **stubbed** | Same layout-engine gap. Same stub approach. | NFR-V2-SAFETY-2 |
| `window.getComputedStyle(el)` (no pseudoElt) | parity | Standard read of computed styles from inline/style-tag CSS | — |
| `window.getComputedStyle(el, "::before").content` | **stubbed** | **Happy-dom ignores the `pseudoElt` second argument entirely** (GH #1773). Returns element's own style or `"none"`. CSS `::before { content: "Subscribe" }` label detection (NFR-SR-V2-9) would never fire. Harness stub routes to fixture-declared pseudo-element content map. Real-Chrome Playwright integration required. | NFR-V2-SAFETY-3 |
| `window.getComputedStyle(el, "::after").content` | **stubbed** | Same as `::before` | NFR-V2-SAFETY-3 |
| `document.elementFromPoint(x, y)` | **integration-only** | **Happy-dom has no layout engine and cannot hit-test.** Returns null or document-root stubs. Clickjack detection (NFR-JS-V2-5) is unverifiable in happy-dom. Playwright + real Chromium is the SOLE authoritative verification. Happy-dom tests MAY spy on invocation shape (arg types, call count) but MUST NOT assert outcome. | NFR-V2-SAFETY-1 |
| `HTMLDialogElement.showModal()` + inert propagation | **integration-only** | Happy-dom does not implement top-layer or automatic `inert`-ing of sibling subtrees. Buttons hidden behind an open modal appear clickable to happy-dom but inert to Chrome. Playwright integration test required. | NFR-V2-SAFETY-5 |
| `[inert]` attribute on static HTML | parity | Happy-dom treats `inert` as a plain attribute readable via `getAttribute`; safety check uses `closest('[inert]')` which works via attribute matching, not live inertness semantics. Accepted. | — |
| `<template>` element inertness | parity | Happy-dom implements `<template>` as an inert document fragment. Safety check only checks `closest('template')` for ancestor presence, not live behavior. | — |
| `<dialog>` element (without `open` attribute) | parity | Same pattern — safety check uses `closest('dialog:not([open]))` attribute matching, not live inertness. | — |
| `Element.prototype.scrollIntoView` | out-of-scope | Happy-dom no-ops scrollIntoView (no viewport). Real-Chrome coverage required if the safety check's dispatch sequence depends on scroll state. For v0.8.0 the call is made but outcome is not asserted. | — |
| `PointerEvent` / `MouseEvent` constructors | parity | Happy-dom supports event construction with all documented properties (`bubbles`, `cancelable`, `view`, `button`, `clientX`, `clientY`, `pointerType`) | — |
| `Element.prototype.dispatchEvent` | parity (partial) | Happy-dom implements dispatch + bubbling but has known bugs (GH #1529 event target null after stopPropagation, #1160 duplicate dispatch). Pinned happy-dom version MUST include fixes. | NFR-V2-SAFETY-4 |
| `MutationObserver` | parity (at pinned version) | Known bugs (GH #394 target missing, #659 disconnect TypeError, #1113 callback 2nd arg) resolved in pinned version. Safety check v0.8.0 does NOT use MutationObserver, so this is aspirational — if future safety checks add it, upgrade to `integration-only` until re-verified. | NFR-V2-SAFETY-4 |
| `SubtleCrypto` / `crypto.subtle.digest` | parity | V8 native, not happy-dom's concern. Used for NFR-V2-FX-4 element fingerprint (future). | — |
| `performance.now()` / `performance.timeOrigin` | parity | V8 native | — |

## Update procedure

When a new DOM API is introduced into `_chrome_safety_check_js` (in `skills/chrome-multi-profile/chrome-lib.sh`):

1. Add a row to this matrix with a status, rationale, and NFR reference
2. If `parity`: no additional action required
3. If `stubbed`: add a stub to `tests/js-fixtures/harness-stubs.mjs` reading from fixture sidecars
4. If `integration-only`: add a Playwright spec to `tests/integration/` that exercises the API with real Chromium
5. If `out-of-scope`: document the reason in the row AND in the test harness code comment

A lint check in `scripts/lint.sh` parses `_chrome_safety_check_js` for DOM API calls and fails if any call is not documented in this file.

## Sources

- happy-dom GH #1416 (`getBoundingClientRect` returns 0)
- happy-dom GH #1773 (`getComputedStyle` ignores pseudoElt arg)
- happy-dom GH #312 (composed event bubbling through ShadowRoot)
- happy-dom GH #394 / #659 / #1113 (MutationObserver bugs)
- happy-dom GH #1529 (event target null after stopPropagation)
- happy-dom GH #1766 (Lit event handling)
- MDN `HTMLDialogElement.showModal` (inert + top-layer spec)
- MDN `Element.getBoundingClientRect` (layout dependency)
