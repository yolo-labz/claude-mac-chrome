# claude-mac-chrome

> **Professional Chrome automation for Claude Code on macOS.**
> Deterministic multi-profile detection via Chrome's own authoritative profile catalog, combined with stable window/tab IDs that don't drift. Zero user configuration. Zero URL heuristics. Zero dependencies.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-7c3aed.svg)](https://code.claude.com/docs/en/plugins)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)]()
[![Zero Dependencies](https://img.shields.io/badge/dependencies-0-success.svg)]()

## The problem

If you're on macOS and you have **multiple Chrome profiles** open — Personal, Work, a client-specific one, a university one — Claude Code's existing Chrome automation tools silently break in a very specific way:

1. Claude runs something like `tell application "Google Chrome" to execute tab 5 of window 1 javascript "..."`
2. Between the time that was written and the time it runs, **z-order reshuffles**: a new tab was created, a notification fired, you Cmd-Tabbed to a different app, or Chrome itself decided to bring a window forward
3. `window 1` is now a **different** Chrome window — a different profile, different cookie jar, different logged-in accounts
4. The JS executes successfully, returns HTTP 200 with a plausible title, and Claude reports success
5. But the tool actually interacted with the wrong account, submitted a form to the wrong service, scraped the wrong inbox, or leaked session state between profiles

The failure is **invisible** — AppleScript has no error, the return value looks normal, and you only discover it later when a form got sent from the wrong email.

Existing tools either hardcode ordinal indices (drift bug unsolved), ask you to hand-configure fingerprint URLs (leaks your infrastructure), or use CDP (blocked by Chrome on the default profile). This plugin does neither.

## The solution

Two insights:

### 1. Chrome already knows all your profiles

Chrome's own `Local State` file at `~/Library/Application Support/Google/Chrome/Local State` is a JSON file that contains an authoritative catalog of every profile on the machine — directory names (`Default`, `Profile 1`, `Profile 3`, ...), human-readable display names (`Personal`, `Work`, `Study`), and the primary Google account email for each. You can read it. You don't need to configure anything.

### 2. Google tab titles contain the signed-in email

When you're signed into Gmail, the tab title is always `"Inbox (N) - you@example.com - Gmail"`. Same for Drive (`"you@example.com - Google Drive"`), Classroom, Docs. Also for ProtonMail, Fastmail, and most other webmails. **Every profile has at least one such tab.** Extract the email from any tab's title in a window, match it against the Local State catalog, and you know exactly which profile that window belongs to.

Combined:

```
~/Library/.../Chrome/Local State
       │
       ▼
  {"Default":    {"name": "Personal", "user_name": "you@gmail.com"},
   "Profile 1":  {"name": "Study",    "user_name": "you@university.edu"},
   "Profile 3":  {"name": "Work",     "user_name": "you@company.com"}}
       │
       │                                ┌─────────────────────────┐
       │                                │  Chrome window IDs are  │
       │                                │  stable AppleScript     │
       │                                │  strings — persist      │
       │                                │  across z-order drift   │
       │                                └────────────┬────────────┘
       │                                             │
       ▼                                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  for each open window:                                        │
  │    for each tab in window:                                    │
  │      extract email from tab.title                             │
  │      if email in catalog: bind window_id → profile            │
  │      break                                                    │
  │                                                               │
  │  →  {"Default":    "100000001",                               │
  │      "Profile 1":  "100000003",                               │
  │      "Profile 3":  "100000004"}                               │
  └──────────────────────────────────────────────────────────────┘
```

Deterministic. Zero user configuration. Zero hardcoded URLs. Zero leaked personal infrastructure in the codebase.

## Stable ID addressing

AppleScript exposes **stable string IDs** for both windows and tabs that persist across z-order reorders, tab reorders, and focus changes:

| Property | Example | Stable across reorders? |
|---|---|---|
| `id of window w` | `"100000001"` | ✅ persists for the lifetime of the window |
| `id of tab t of window w` | `"100000002"` | ✅ persists for the lifetime of the tab |
| `index of window w` | `1` | ❌ reshuffles on every focus change |
| `tab 5 of window 1` | (ordinal) | ❌ reshuffles on every new tab |

AppleScript also supports direct-ID addressing:

```applescript
tell application "Google Chrome"
  set title_result to execute (tab id "100000002" of window id "100000001") javascript "document.title"
  set URL of (tab id "100000002" of window id "100000001") to "https://example.com"
end tell
```

This plugin wraps everything into a zero-dependency shell library (`chrome-lib.sh`) that Claude Code can call.

## Install

```bash
# In Claude Code:
/plugin marketplace add yolo-labz/claude-mac-chrome
/plugin install claude-mac-chrome@claude-mac-chrome
```

Alternative — clone locally:

```bash
git clone https://github.com/yolo-labz/claude-mac-chrome.git ~/.claude/plugins/local/claude-mac-chrome
/plugin marketplace add ~/.claude/plugins/local/claude-mac-chrome
```

## One-time setup

**Enable JavaScript from Apple Events** in every Chrome profile you want to automate:

> Chrome → View → Developer → Allow JavaScript from Apple Events

This is a per-profile setting, so you may need to do it once in each profile's window. Without it, `execute ... javascript` returns `missing value` regardless of the JS.

## Quick start

```bash
LIB="${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh"

# Dump the profile catalog from Chrome's Local State
$LIB catalog

# Build the window-to-profile mapping (scans all open windows, extracts emails from tab titles)
$LIB fingerprint

# Human-readable diagnostic
$LIB debug
# Profile catalog (from Chrome Local State):
#   [Default     ] Personal                    you@gmail.com
#   [Profile 1   ] Study                       you@university.edu
#   [Profile 3   ] Work                        you@company.com
#
# Matched windows:
#   win id=100000001  Default    Personal  you@gmail.com
#   win id=100000003  Profile 1  Study     you@university.edu
#   win id=100000004  Profile 3  Work      you@company.com

# Get a window by any kind of reference — display name, email, profile dir, substring
WIN=$($LIB window_for "Work")              # substring of display name
WIN=$($LIB window_for "you@company.com")   # exact email
WIN=$($LIB window_for "Profile 3")         # exact profile directory
WIN=$($LIB window_for "company.com")       # substring of email

# Find a specific tab in that window
TAB=$($LIB tab_for_url "$WIN" "mail.google.com")

# Run JavaScript
$LIB js "$WIN" "$TAB" "document.title"

# Navigate
$LIB navigate "$WIN" "$TAB" "https://mail.google.com/mail/u/0/#inbox"

# Create a new tab, capture its stable ID
NEW_TAB=$($LIB new_tab "$WIN" "https://example.com")

# Force cache refresh (after opening/closing windows or restarting Chrome)
$LIB refresh
```

Or source it into a bash script:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh"
WIN=$(chrome_window_for "Work")
TAB=$(chrome_tab_for_url "$WIN" "github.com")
chrome_js "$WIN" "$TAB" "document.querySelectorAll('.notification-count').length + ''"
```

## Role aliases (optional)

If you want Claude to use semantic names like `work` / `school` / `personal` rather than memorizing your specific profile display names, create `~/.config/claude-mac-chrome/roles.json`:

```json
{
  "work": "Work",
  "school": "Uni",
  "personal": "Personal"
}
```

Values can be any reference `chrome_window_for` accepts (profile directory, display name, email, or substring of any). The file is stored in your XDG config dir, **never committed to any repository**, and entirely optional.

## Comparison with existing tools

| Feature | **claude-mac-chrome** | Playwright | CDP | [SpillwaveSolutions/automating-chrome](https://github.com/SpillwaveSolutions/automating-mac-apps-plugin) | [obra/superpowers-chrome](https://github.com/obra/superpowers-chrome) |
|---|---|---|---|---|---|
| Works with logged-in sessions | ✅ | ❌ (fresh profile) | ❌ (blocked on default) | ✅ | ❌ (fresh profile) |
| Multi-profile awareness | ✅ deterministic | ❌ | ❌ | ❌ | ❌ |
| Authoritative profile catalog (no user config) | ✅ | n/a | n/a | ❌ | ❌ |
| Stable ID addressing | ✅ | n/a | ✅ | ❌ (ordinal) | ✅ (CDP targetId) |
| Survives z-order shuffles | ✅ | n/a | ✅ | ❌ | ✅ |
| Zero dependencies | ✅ (bash + osascript) | ❌ (Node + browsers) | ❌ (client lib) | ❌ (JXA + PyXA) | ❌ (Node) |
| macOS-native | ✅ | cross-platform | cross-platform | ✅ | cross-platform |
| Zero leaked personal URLs in defaults | ✅ | n/a | n/a | n/a | n/a |

## Why not Playwright / CDP / the official Claude in Chrome extension?

| Approach | Problem on macOS multi-profile |
|---|---|
| Playwright | Launches a fresh throwaway Chrome profile with no cookies — can't access your logged-in sessions |
| CDP via `--remote-debugging-port` | **Chrome blocks CDP on the default profile by Apple security policy** — connection refused silently |
| Claude in Chrome extension | Only runs in the browser-side agent loop; falls apart for headless/overnight Claude Code CLI sessions |
| `chrome-cli` (prasmussen) | Single-profile, uses ordinal indices, no multi-profile awareness |
| `obra/superpowers-chrome` | Node.js + CDP — same blocking issue on the default profile |
| `SpillwaveSolutions/automating-chrome` | JXA + AppleScript, but uses ordinal `chrome.windows[0].tabs[0]` — same drift bug |

AppleScript runs as the real user, with the real cookie jar, in the real running Chrome process, without CDP or extensions. It's the only approach that actually works for "drive my logged-in Gmail in the Work profile while not touching the Personal one."

## Known limitations

- **macOS only.** AppleScript is the mechanism. Linux/Windows users should look at Playwright or CDP with a throwaway profile.
- **Requires "Allow JavaScript from Apple Events" per profile.** One-time setup in each profile's window.
- **Can't do headless.** This is explicitly about driving *your real, logged-in, visible Chrome*.
- **Requires at least one email-bearing tab per window you want to auto-match.** Pin Gmail or ProtonMail in each profile. (Profiles without any email-bearing tab can still be addressed by profile directory name — `chrome_window_for "Profile 3"`.)
- **No DOM events interception, no network interception.** For that level of control, use Playwright with a throwaway profile.
- **IDs reset when Chrome restarts.** The library auto-detects stale cache via `exists window id "..."` and re-scans.
- **Windows on a different macOS Space** may not be enumerated by `every window` until they've been touched since Chrome started. Workaround: bring the missing window forward once, then `chrome-lib.sh refresh`.

## Commands

This plugin ships one slash command:

- **`/chrome-debug`** — dumps the profile catalog and matched windows in a human-readable table

## Contributing

Contributions welcome. Places to extend:

1. **More webmail title patterns** — the email-extraction regex is generic, but some providers have unusual title formats. PRs that add a known-good pattern for your provider are welcome.
2. **Role alias presets** for common profile setups (Google Workspace + personal Gmail, corporate Microsoft + personal, etc.).
3. **More JS injection recipes** in `skills/chrome-multi-profile/docs/patterns.md`.
4. **Authentication check selectors** for more sites — these go in `SKILL.md` and `docs/patterns.md`.
5. **Cross-validation with process inspection** — `ps aux | grep -- --profile-directory=` gives per-renderer process info; a future version could cross-check email extraction against renderer PID ownership for defense-in-depth.

File issues at https://github.com/yolo-labz/claude-mac-chrome/issues.

## Troubleshooting

**Claude says Chrome isn't running but Chrome is clearly open.**
Check `System Settings → Privacy & Security → Automation` and confirm Claude Code has permission to control "Google Chrome". macOS TCC silently blocks Apple Events otherwise.

**`chrome_window_for` returns "not_open" for a profile I know is open.**
Run `chrome-lib.sh fingerprint | jq` and verify the profile appears in the `by_dir` and `by_email` maps. If it doesn't, the profile hasn't been opened yet in this Chrome session — open any tab in it first, then retry. The library queries live Chrome state, not just the catalog.

**`chrome_click` returns `blocked_reason: purchase_button_text_depth_0` on a button I want to click.**
That's the safety gauntlet working as designed. The trigger lexicon matched "Upgrade", "Comprar", "Subscribe", or a similar word in the button's text, an ancestor, or an attribute. If this is legitimate, add `--confirm-purchase=<exact text>` — you'll still be asked to confirm on the terminal.

**`chrome_click` returns `blocked_reason: payment_field_lock` on an unrelated button.**
The page has a credit-card input somewhere on it. The safety check refuses to click ANY button on a page with payment fields as a defense-in-depth measure. Use `chrome_query` to read the DOM instead, or dispatch the click via the Chrome UI directly.

**Rate limited: "10 clicks per 60s exceeded".**
Give it a minute. The rate limiter is per-verb (click, query, wait_for), so you can still use read-only operations during the cooldown. To change the limit, edit the constant in `chrome-lib.sh` — but note that the default was chosen to prevent runaway agents.

**`tests/run.sh` fails with "happy-dom not vendored yet".**
Run `scripts/verify-vendor.sh` or wait until the release ceremony has produced `tests/vendor/happy-dom.mjs`. The JS fixture suite is skipped cleanly if the vendor bundle isn't present.

**Bats tests pass locally but CI fails on `rate_limiter`.**
The rate limiter's fail-closed check includes a wrong-uid test that assumes Linux file ownership semantics. macOS and Linux diverge on `stat` format strings. See `tests/bats/04-rate-limiter.bats` for the dual-format handling.

**`gpg --verify SHA256SUMS.asc SHA256SUMS` fails after download.**
Ensure you downloaded the `.asc` file alongside the `SHA256SUMS` file AND imported the maintainer's public GPG key. Fingerprint is published in `SECURITY.md`. If the key has been rotated, a new fingerprint will be pinned at the top of SECURITY.md with a timestamp.

**`cosign verify-blob` fails with "certificate identity mismatch".**
Verify your cosign CLI is ≥ v2.4.0. The `--certificate-identity-regexp` flag enforces that the signer was a GitHub Actions run on the yolo-labz/claude-mac-chrome repository. If the regex doesn't match, the binary may have been signed by an attacker's workflow — do not install.

**`scripts/build-release.sh` produces different SHA-256 on two runs.**
Reproducibility is broken. Most likely cause: non-GNU `tar` in PATH (brew install gnu-tar), or `SOURCE_DATE_EPOCH` unset. Run `tar --version` to confirm GNU tar is being used. If the mismatch persists, diffoscope the two tarballs to locate the drift.

## FAQ

**Q: Why not use CDP (Chrome DevTools Protocol)?**
A: Chromium M122+ blocks CDP on the default profile to prevent cookie theft. The only bypass is the `DevToolsRemoteDebuggingAllowed` enterprise policy, which broadcasts attack surface in `chrome://policy`. Principle II of the constitution forbids this.

**Q: Why not use a headless Chromium?**
A: The whole point is to automate your REAL Chrome profiles with your REAL cookies. A headless instance discards every login. The motivating use case was never "run a bot" — it was "let Claude check my Gmail for me".

**Q: Why does this require macOS?**
A: Because the library talks to Chrome via Apple Events + AppleScript. A Linux port would need to use xdotool/wmctrl/ydotool — a completely different architecture. v1.2.0 may port it; see `docs/MIGRATION-0.x-to-1.0.md`.

**Q: Why do I need to confirm purchases on the TTY?**
A: Because the motivating incident was an AI accidentally subscribing to a 1-month Proton Mail plan instead of 12-month. The entire safety gauntlet exists to make that kind of mistake mechanically impossible. TTY confirmation is the final backstop.

**Q: Is the Portuguese trigger lexicon really mandatory?**
A: Yes, for me. I have two Chrome profiles (UFPE and Sciensa) that regularly load pt-BR checkout pages. Without the pt-BR tokens (`comprar`, `assinar`, `pagar`, `finalizar`, `contratar`), an English-only regex would cheerfully click "Comprar agora". The lexicon is tested by `tests/bats/03-lexicon-loader.bats`.

**Q: Does this plugin call any external APIs?**
A: No. Zero network calls. Zero telemetry. Everything is local.

**Q: Can I use this with Arc / Brave / Edge?**
A: Not in v1.0.0. Arc/Brave/Edge share Chrome's AppleScript dictionary but the `Local State` layout and profile detection differ. Cross-browser support is on the v1.1.0 roadmap.

**Q: How do I update the trigger lexicon?**
A: Edit `skills/chrome-multi-profile/lexicon/triggers.txt`, one token per line, comments allowed with `#`. Run `tests/bats/03-lexicon-loader.bats` to verify your additions parse. PRs touching the lexicon are security-reviewed via CODEOWNERS.

## Security

See [SECURITY.md](SECURITY.md) for the disclosure policy and release verification procedure.

Highlights:
- 15-layer safety gauntlet on `chrome_click` (URL blocklist, trigger lexicon with pt-BR, Unicode normalization + zero-width strip, shadow DOM walker, pseudo-element extractor, payment field lock, inert container check, visibility + zero-dim check, clickjack hit-test, rate limiter, audit log, TTY confirm, prompt injection scanner, domain allowlist, 3-ancestor attribute walk)
- Signed releases: cosign keyless + SLSA L3 + CycloneDX 1.7 + SPDX 2.3 SBOMs
- Reproducible builds verified byte-by-byte in CI
- Weekly OSV-Scanner on vendored dependencies
- OpenSSF Scorecard ≥ 7.0

## Privacy

- The library reads the local user's `~/Library/Application Support/Google/Chrome/Local State` file. This contains email addresses and profile names. The data **never leaves your machine** — it's used only to build an in-memory mapping and optionally cached at `/tmp/chrome-fingerprint.json`.
- No network calls.
- No telemetry.
- No hardcoded URLs in the defaults — the library reads YOUR profiles, not ours.
- The optional `~/.config/claude-mac-chrome/roles.json` file is user-local and never committed anywhere.
- An audit log of every `chrome_click` dispatch is written to `~/Library/Logs/claude-mac-chrome/audit.jsonl` (mode 0600, append-only). This is LOCAL ONLY.

## Verifying releases

The simplest way to verify a release is with the GitHub CLI (`gh >= 2.49.0`):

```bash
# Download the release tarball
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/latest/download/claude-mac-chrome.tar.gz

# Verify provenance attestation (checks Sigstore signature + SLSA provenance)
gh attestation verify ./claude-mac-chrome.tar.gz \
  --repo yolo-labz/claude-mac-chrome \
  --signer-workflow yolo-labz/claude-mac-chrome/.github/workflows/release.yml
```

If verification fails, **do not install**. File a security advisory.

### Advanced / Offline verification

For environments without `gh`, you can verify using cosign or slsa-verifier directly:

```bash
# Download the release and its signature bundle
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/latest/download/claude-mac-chrome.tar.gz
curl -sLO https://github.com/yolo-labz/claude-mac-chrome/releases/latest/download/claude-mac-chrome.tar.gz.sigstore

# Verify the cosign keyless signature
cosign verify-blob \
  --certificate-identity-regexp 'https://github.com/yolo-labz/claude-mac-chrome/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --bundle claude-mac-chrome.tar.gz.sigstore \
  claude-mac-chrome.tar.gz
```

## License

MIT — see [LICENSE](LICENSE).

## Credits

Prior art:

- **[obra/superpowers-chrome](https://github.com/obra/superpowers-chrome)** — the CDP-based Claude Code plugin that proved the demand for reliable Chrome automation in this ecosystem
- **[SpillwaveSolutions/automating-mac-apps-plugin](https://github.com/SpillwaveSolutions/automating-mac-apps-plugin)** — broad JXA automation coverage for macOS apps including Chrome; uses ordinal addressing
- **[prasmussen/chrome-cli](https://github.com/prasmussen/chrome-cli)** — the classic Chrome AppleScript CLI
- **[Hammerspoon ChromeProfileSwitcher.spoon](https://github.com/Hammerspoon/Spoons)** — Lua automation library that inspired the Local State parsing approach

The insight that Chrome's own `Local State` file can serve as an authoritative profile catalog, combined with extracting signed-in emails from Google/webmail tab titles, is the core of this plugin. Both techniques are documented in Chromium source and work reliably across Chrome versions.

## See also (yolo-labz ecosystem)

- [yolo-labz/linkedin-chrome-copilot](https://github.com/yolo-labz/linkedin-chrome-copilot) — LinkedIn copilot that delegates 100% of Chrome I/O to this plugin via `tools/chrome-shim.sh`. Reference downstream consumer.
- [yolo-labz/wa](https://github.com/yolo-labz/wa) — WhatsApp daemon that composes for cross-app pipelines (browser → messaging → save-state).
- [yolo-labz/kokoro-speakd](https://github.com/yolo-labz/kokoro-speakd) — TTS daemon for spoken status feedback during long browser-automation runs.
- Architecture deep-dives on multi-profile detection + cliclick + isTrusted bypass: [blog.home301server.com.br](https://blog.home301server.com.br).
- Author portfolio: [portfolio.home301server.com.br](https://portfolio.home301server.com.br).
