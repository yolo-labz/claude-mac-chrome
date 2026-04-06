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

## Security and privacy

- The library reads the local user's `~/Library/Application Support/Google/Chrome/Local State` file. This contains email addresses and profile names. The data **never leaves your machine** — it's used only to build an in-memory mapping and optionally cached at `/tmp/chrome-fingerprint.json`.
- No network calls.
- No telemetry.
- No hardcoded URLs in the defaults — the library reads YOUR profiles, not ours.
- The optional `~/.config/claude-mac-chrome/roles.json` file is user-local and never committed anywhere.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Prior art:

- **[obra/superpowers-chrome](https://github.com/obra/superpowers-chrome)** — the CDP-based Claude Code plugin that proved the demand for reliable Chrome automation in this ecosystem
- **[SpillwaveSolutions/automating-mac-apps-plugin](https://github.com/SpillwaveSolutions/automating-mac-apps-plugin)** — broad JXA automation coverage for macOS apps including Chrome; uses ordinal addressing
- **[prasmussen/chrome-cli](https://github.com/prasmussen/chrome-cli)** — the classic Chrome AppleScript CLI
- **[Hammerspoon ChromeProfileSwitcher.spoon](https://github.com/Hammerspoon/Spoons)** — Lua automation library that inspired the Local State parsing approach

The insight that Chrome's own `Local State` file can serve as an authoritative profile catalog, combined with extracting signed-in emails from Google/webmail tab titles, is the core of this plugin. Both techniques are documented in Chromium source and work reliably across Chrome versions.
