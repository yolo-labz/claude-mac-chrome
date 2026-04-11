# Threat Model — claude-mac-chrome v1.0.0

**Purpose:** Enable external security review of claude-mac-chrome before v1.0.0 general availability. Per spec §NFR-V2-CRA-1.

**Methodology:** STRIDE (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege).

**Scope:** The claude-mac-chrome skill as installed on a user's macOS machine + invoked by Claude Code on the same machine. Out of scope: compromises of the user's machine itself, of the Chrome browser binary, or of macOS.

## 1. System overview

claude-mac-chrome is a bash+AppleScript library that gives Claude Code deterministic access to the user's existing Chrome profiles on macOS. It:

- Reads Chrome's `Local State` JSON catalog to list profiles
- Talks to the Chrome application via AppleScript (NOT CDP, NOT extensions)
- Executes constrained DOM queries and safety-gated click dispatch via `execute javascript` inside existing tabs
- Uses AppleScript stable string IDs (`id of window`, `id of tab`) — not pointer-based

## 2. Assets

| Asset | Sensitivity | Storage |
|---|---|---|
| User cookies / session state | HIGH | Chrome profile directory (`~/Library/Application Support/Google/Chrome/<Profile>`) |
| OAuth tokens | HIGH | Same |
| Browser history | MEDIUM | Same |
| Chrome profile list (emails, avatar URLs) | LOW | Local State JSON |
| User's local filesystem | HIGH | macOS user dir |
| Claude conversation history | MEDIUM | Claude Code's own storage |

## 3. Trust boundaries

```
[Claude LLM]  ←— network —  [Claude Code CLI]  ←— bash —  [chrome-lib.sh]  ←— AppleScript —  [Chrome.app]  ←— DOM —  [website]
     T1                            T2                            T3                            T4                      T5
```

- **T1/T2**: User trusts Claude Code to reflect Claude's intent faithfully
- **T2/T3**: chrome-lib.sh trusts Claude Code to pass selector strings verbatim (UNTRUSTED from chrome-lib's perspective — treated as adversarial input)
- **T3/T4**: AppleScript talks to Chrome via macOS Apple Events — macOS TCC enforces permission
- **T4/T5**: Chrome renders untrusted web content; all DOM reads MUST assume arbitrary attacker control

## 4. STRIDE analysis

### Spoofing

| Threat | Mitigation |
|---|---|
| Malicious webpage mimics legitimate UI to trick Claude into clicking "Upgrade" | 15-layer safety check (NFR-SR-V2-*): trigger lexicon, Unicode normalization, confusables fold, attribute walk, shadow DOM descent, pseudo-element extraction |
| Fake profile in Local State JSON | Local State is written only by Chrome; compromise requires prior Chrome RCE (out of scope) |
| Window ID reuse by a newer window | AppleScript stable string IDs are immutable for window lifetime; `chrome_snapshot` captures IDs that become invalid after close (fails closed) |

### Tampering

| Threat | Mitigation |
|---|---|
| Attacker modifies chrome-lib.sh at rest | Cosign signature verification on release tarball (NFR-V2-DEV-3) |
| Man-in-the-middle on happy-dom vendor bundle refresh | `VENDOR-MANIFEST.json` pins commit + tarball SHA; `verify-vendor.sh` re-derives and diffs |
| User data overwritten during `chrome_restore` | Restore refuses to run if any targeted window no longer exists (stable-ID check) |

### Repudiation

| Threat | Mitigation |
|---|---|
| Denial that a chrome_click happened | JSONL audit log at `~/Library/Logs/claude-mac-chrome/audit.jsonl`, 0600, append-only. Future: `chflags uappnd` (NFR-SR-V2-AUDIT-5) |
| Log injection via adversarial URL | `jq -Rs .` encoding in every write; control-char stripping (bats 05) |

### Information disclosure

| Threat | Mitigation |
|---|---|
| Cookie-jar exfiltration via `chrome_js` eval | `chrome_js` is constrained to read-only envelope fields; no raw cookie dump helper exists in public API |
| AppleScript injection via selector string | `jq -Rs .` parameterization. Tests in `tests/bats/08-json-stringify.bats` assert escaping. |
| Profile list leak to stdout when piped | chrome_fingerprint output is machine-readable JSON by design; user is expected to pipe only to trusted consumers |

### Denial of service

| Threat | Mitigation |
|---|---|
| Rate-limit exhaustion (accidental or adversarial) | `_chrome_rate_limit_check` 10/60s floor + global cap |
| Infinite loop in gatherAllText shadow DOM descent | Depth cap at 10 + element cap at 100 per level |
| Slow DOM script blocks Chrome | `osascript` timeout inherited from AppleScript Apple-Event timeout |

### Elevation of privilege

| Threat | Mitigation |
|---|---|
| Safety check bypass allows accidental purchase | The 15 rails + URL blocklist + payment field lock + confirmation gate |
| Extension or CDP escape | **Non-goal**: claude-mac-chrome explicitly does NOT use CDP or extensions. Principle II of the project constitution. |
| Throwaway profile escape of user's real cookies | **Non-goal**: throwaway/sandbox profiles forbidden (Principle II) |

## 5. Non-goals (important)

- **Not a sandbox**: operates on the user's real Chrome profiles by design
- **Not a CDP client**: does not attach a debugger; no `--remote-debugging-port`
- **Not an extension**: no `.crx`, no `chrome.tabs.*`, no extension APIs
- **Not a password manager**: does not read form autofill, does not enumerate saved credentials
- **Not a replacement for user judgment**: the safety gauntlet is defense-in-depth, not a guarantee. The final reviewer is the human.

## 6. New attack surface added by vendored happy-dom

The vendored `tests/vendor/happy-dom.mjs` runs only in **test contexts**, never at runtime. It is:

- Isolated to `tests/` (see `.gitignore` patterns in release tarball)
- Byte-verified in CI by `scripts/verify-vendor.sh`
- Scanned weekly by `.github/workflows/osv-scan.yml`
- Documented with a refresh policy (`tests/VENDOR-POLICY.md`)

## 7. Review checklist

External reviewers should especially examine:

1. `skills/chrome-multi-profile/chrome-lib.sh`: `_chrome_safety_check_js`, `chrome_click`, `_chrome_check_url_blocklist`
2. `skills/chrome-multi-profile/lexicon/triggers.txt`: completeness of the trigger lexicon (English + pt-BR MANDATORY)
3. Rate limiter state file handling: `_chrome_rate_limit_check` — fail-closed on corruption, future mtime, wrong uid
4. Audit log control-character stripping: bats 05
5. `jq -Rs .` escaping: bats 08
6. happy-dom fidelity matrix: `docs/HAPPY-DOM-FIDELITY.md` — any API marked `parity` that is actually stubbed is a defect
