# Migration Guide — 0.x → 1.0.0

**TL;DR:** No breaking changes to the public function surface. v1.0.0 is a hardening + verification release, not a rewrite.

## Commit range

- Start of 0.x: `797845c` (v0.2.0 initial skill release)
- End of 0.x: the commit immediately preceding the `v1.0.0` signed tag

## Renamed functions

*None.*

## Removed functions

*None.*

All 0.x public functions are preserved with identical signatures.

## Changed behavior

### `chrome_click` (v0.8.0+)

`chrome_click` gained a 15-layer safety gauntlet. **Callers written for v0.7.x or earlier will continue to work unchanged**, but may now receive blocked envelopes for clicks that previously dispatched unconditionally.

**Before v0.8.0:**
```bash
chrome_click "$win" "$tab" "#submit"  # always dispatched
```

**v0.8.0+:**
```bash
chrome_click "$win" "$tab" "#submit"
# Returns envelope with ok=false + blocked_reason if:
#   - URL matches blocklist (Stripe, PayPal, etc.)
#   - Element text matches trigger lexicon (Upgrade, Comprar, etc.)
#   - Element is inside an inert ancestor, hidden, or zero-size
#   - Payment fields are present anywhere on the page
```

**Remedy:** Check the envelope's `ok` field. If `ok: false`, consult `blocked_reason` and decide whether to surface the block to the user or override via `--confirm-purchase=<text>` (which still requires TTY confirmation).

### `chrome_snapshot` / `chrome_restore` (v0.7.0+)

These are new in 0.x. No migration needed.

## Profile detection (v0.4.0)

v0.4.0 removed the SNSS parser and replaced it with live URL overlap. Callers of `chrome_window_for` and related lookup helpers see no API change, but the detection is now authoritative rather than probabilistic.

## Removed dependencies

- **Python 3**: v0.4.0 rewrote all Python heredocs as `jq` + bash. `python3` is no longer a runtime dependency. Skill now requires only `bash ≥ 5`, `jq`, `osascript`.

## sed-scriptable rewrite rules

*None required* — no identifier renames.

## Verifying v1.0.0 signatures

```bash
# Download the release
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/download/v1.0.0/claude-mac-chrome.tar.gz
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/download/v1.0.0/claude-mac-chrome.tar.gz.sigstore

# Verify with cosign (keyless)
cosign verify-blob \
  --certificate-identity-regexp 'https://github.com/yolo-labz/claude-mac-chrome/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --bundle claude-mac-chrome.tar.gz.sigstore \
  claude-mac-chrome.tar.gz
```

## Upgrading

```bash
# From Claude Code plugin marketplace (recommended)
/plugin update claude-mac-chrome

# Or from a release tarball (after cosign verification)
tar xzf claude-mac-chrome.tar.gz -C ~/.claude/plugins/
```
