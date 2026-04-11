# Public API Reference — v1.0.0

This document is the **frozen public API contract** for claude-mac-chrome v1.0.0. Per Principle V of the project constitution (Public API Stability), functions listed here cannot be renamed or have their argument order changed without a MAJOR version bump.

All functions are defined in `skills/chrome-multi-profile/chrome-lib.sh` and exported for `source` usage.

## Conventions

- **Return format:** All public functions emit a single-line JSON envelope on stdout. Exit 0 on success, non-zero on failure. Envelopes always contain at minimum: `ok` (boolean), `error` (string, when `ok: false`).
- **Window/tab addressing:** All functions use AppleScript stable string IDs. These are immutable for the lifetime of the window/tab and survive reflows, reorderings, and tab drags.
- **No positional overloading:** Each function has exactly one calling convention.

---

## Discovery

### `chrome_fingerprint`

List all Chrome profiles authoritatively from `Local State` JSON catalog.

**Signature:**
```bash
chrome_fingerprint
```

**Returns:** NDJSON — one line per profile. Each line is an object with fields: `profile_dir`, `user_name`, `gaia_id`, `given_name`, `avatar_url`, `is_default`.

---

### `chrome_window_for`

Resolve a profile email or profile dir to a currently-open Chrome window's stable ID.

**Signature:**
```bash
chrome_window_for <email_or_profile_dir>
```

**Returns:** Envelope with `window_id` (string), `tab_count` (int), or `error: "not_open"`.

---

### `chrome_tab_for_url`

Find the first tab (across all windows of a given profile) whose URL matches a pattern.

**Signature:**
```bash
chrome_tab_for_url <window_id> <url_substring>
```

**Returns:** Envelope with `tab_id`, `url`, `title`, or `error: "not_found"`.

---

## Routing

### `chrome_route_url`

Composite "find-or-open" — open the URL in the target profile, reusing an existing tab if present.

**Signature:**
```bash
chrome_route_url <email_or_profile_dir> <url>
```

**Returns:** Envelope with `window_id`, `tab_id`, `action` (one of `reused`, `opened_new_tab`, `opened_new_window`).

---

## DOM actions (safety-gated)

### `chrome_click`

The core safety-gated click primitive. Runs a 15-layer verification gauntlet before dispatching.

**Signature:**
```bash
chrome_click [--dry-run] [--confirm-purchase=<exact_text>] <window_id> <tab_id> <selector>
```

**Flags:**
- `--dry-run`: Run all checks but do NOT dispatch the click. Envelope includes `dry_run: true`.
- `--confirm-purchase=<text>`: Acknowledge a blocklist hit. Requires TTY confirmation even with this flag set.

**Returns:** Envelope with `ok` (true iff dispatched), `blocked_reason` (enum, see below), `fired_rail_trace` (array), `elapsed_ms`.

**blocked_reason enum:**
- `element_not_found`
- `url_blocklisted`
- `purchase_button_text_depth_0..2`
- `purchase_button_attr_<attr>_depth_0..2`
- `payment_field_lock`
- `inert_container`
- `not_visible`
- `zero_dimensions`
- `clickjack_suspected`
- `rate_limited`
- `js_error`

---

### `chrome_query`

Read-only DOM query. Returns text or attribute values. No dispatch. No safety gauntlet (read-only).

**Signature:**
```bash
chrome_query <window_id> <tab_id> <selector> [attr|text]
```

**Returns:** Envelope with `value`, `found`.

---

### `chrome_wait_for`

Poll for a selector to appear. Bounded timeout.

**Signature:**
```bash
chrome_wait_for <window_id> <tab_id> <selector> [--timeout=<ms>]
```

---

## Workflow orchestration

### `chrome_check_inboxes`

Check all known mail provider tabs for unread count + snippet.

**Signature:**
```bash
chrome_check_inboxes
```

**Returns:** NDJSON — one line per inbox.

---

### `chrome_snapshot` / `chrome_restore`

Capture / restore the current window+tab layout of a profile.

**Signatures:**
```bash
chrome_snapshot <email_or_profile_dir> <snapshot_name>
chrome_restore <email_or_profile_dir> <snapshot_name>
```

---

## Private functions (NOT part of the stable API)

Functions prefixed with `_chrome_` or `_emit_` are implementation details and MAY change without notice. Do not call them from consumer scripts.

Currently present underscore-prefixed helpers (non-exhaustive):
- `_chrome_check_url_blocklist`
- `_chrome_check_domain_allowlist`
- `_chrome_safety_check_js`
- `_chrome_rate_limit_check`
- `_chrome_audit_log`
- `_chrome_check_prompt_injection`
- `_chrome_load_trigger_lexicon`
- `_emit_safety_js` (hidden CLI verb for test harness only)

## Envelope schema contract

Every public function's stdout JSON envelope conforms to:

```typescript
interface Envelope {
  ok: boolean;
  action: string;
  elapsed_ms: number;
  error?: string;          // only when ok:false
  reason?: string;         // structured sub-reason
  value?: unknown;         // function-specific payload
  fired_rail_trace?: string[];  // chrome_click only
  blocked_reason?: string; // chrome_click only
}
```

Consumers MUST tolerate unknown fields (forward-compat).
