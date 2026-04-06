---
name: chrome-multi-profile
description: Reliably automate Chrome on macOS across multiple profiles (Personal / Work / School / etc.) using Chrome's own authoritative profile catalog (Local State file) combined with stable window/tab IDs. Use when asked to drive a Chrome tab, read a Gmail/ProtonMail inbox, fill a form, scrape a page, or automate anything in a specific Chrome window — especially when the user has multiple Chrome windows open simultaneously. Zero user configuration — reads the user's own Chrome profiles and matches them to open windows via email addresses embedded in tab titles.
allowed-tools:
  - Bash
  - Read
---

# Chrome Multi-Profile Automation (macOS)

Most Chrome automation tooling on macOS addresses windows and tabs by ordinal index (`window 1`, `tab 5`). This silently breaks when the user has multiple Chrome windows open (one per profile — Personal / Work / School), because z-order reshuffles on every focus change, tab creation, or notification. The tool call returns HTTP 200 with a plausible-looking title, but the JavaScript executed in the wrong profile's DOM, form submissions went to the wrong account, and cookies came from the wrong profile.

This skill fixes it with a professional, **deterministic** approach that needs zero user configuration:

1. **Read Chrome's own Local State file** (`~/Library/Application Support/Google/Chrome/Local State`) to get the authoritative catalog of profiles on this machine — directory names, display names, and signed-in Google account emails.
2. **Extract email addresses from tab titles** in each open window. Every Gmail/Calendar/Drive/Docs/YouTube/Classroom tab's `title` property contains the signed-in account email (e.g., `"Inbox (10) - you@example.com - Gmail"`).
3. **Match emails to the catalog** → for each open window, you know which profile directory it belongs to, its human-readable name, and its Google account.
4. **Address windows and tabs by their stable string IDs** (`id of window w`, `id of tab t of window w`) — these persist across z-order reorders, tab reorders, and focus changes. They only reset when Chrome restarts, and the library auto-detects that.

The result is a single deterministic mapping: `"Work profile" → stable window ID → stable tab ID → JavaScript execution`. Zero drift, zero user configuration, zero personal-info hardcoding.

## Trigger conditions

Use this skill whenever you need to:

- List, read, or drive Chrome tabs on macOS
- Distinguish between Chrome profiles (personal / work / school / client-specific / etc.)
- Execute JavaScript in a specific profile's tab without risking wrong-profile drift
- Fill forms, scrape content, navigate, or extract data from sessions where the login only exists on one profile
- Build overnight/cron automation that must reliably hit the same tab across many Claude sessions

## Core facts

| Property | Example | Stable? |
|---|---|---|
| `id of window w` | `"100000001"` | ✅ persists for the lifetime of the window |
| `id of tab t of window w` | `"100000002"` | ✅ persists for the lifetime of the tab |
| `index of window w` | `1` | ❌ reshuffles on every focus change |
| `tab 5 of window 1` | (ordinal) | ❌ reshuffles on every new tab |

**AppleScript supports direct-ID addressing:**

```applescript
tell application "Google Chrome"
  set t to execute (tab id "100000002" of window id "100000001") javascript "document.title"
  set URL of (tab id "100000002" of window id "100000001") to "https://example.com"
end tell
```

## Quick start

The library at `${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh` handles everything. Either invoke it as a CLI or source it into your shell.

```bash
LIB="${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh"

# List every profile Chrome knows about, from its Local State file
$LIB catalog
# → {"Default": {"dir":"Default","name":"Personal","user_name":"you@gmail.com",...}, ...}

# Build the full fingerprint mapping (catalog + window matching)
$LIB fingerprint

# Human-readable diagnostic
$LIB debug
# Profile catalog (from Chrome Local State):
#   [Default     ] Personal                    you@gmail.com
#   [Profile 1   ] Study                       you@university.edu
#   [Profile 3   ] Work                        you@company.com
#
# Matched windows:
#   win id=100000001  Default    Personal     you@gmail.com
#   win id=100000003  Profile 1  Study        you@university.edu
#   win id=100000004  Profile 3  Work         you@company.com

# Get a window by any kind of reference — display name, email, profile dir, substring
WIN=$($LIB window_for "Work")              # substring of display name
WIN=$($LIB window_for "you@company.com")   # exact email
WIN=$($LIB window_for "Profile 3")         # exact profile directory
WIN=$($LIB window_for "company.com")       # substring of email

# Find a tab in that window by URL substring
TAB=$($LIB tab_for_url "$WIN" "mail.google.com")

# Run JavaScript
$LIB js "$WIN" "$TAB" "document.title"

# Navigate
$LIB navigate "$WIN" "$TAB" "https://mail.google.com/mail/u/0/#inbox"

# Create a new tab, capture its stable ID
NEW=$($LIB new_tab "$WIN" "https://example.com")

# Force cache refresh (after opening/closing windows or restarting Chrome)
$LIB refresh
```

**Shell-source usage** (inside a bigger script):

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh"
WIN=$(chrome_window_for "Work")
TAB=$(chrome_tab_for_url "$WIN" "mail.google.com")
chrome_js "$WIN" "$TAB" "document.querySelectorAll('tr.zA').length + ''"
```

## Profile detection — how it actually works

The library is deterministic and needs zero user config. Here's the flow on every `fingerprint` call:

### Step 1 — Read the authoritative catalog

`~/Library/Application Support/Google/Chrome/Local State` is a JSON file Chrome itself maintains. It contains `profile.info_cache` — a dictionary of every profile, keyed by directory name (`Default`, `Profile 1`, `Profile 3`, ...), with metadata:

```json
{
  "Default": {
    "name": "Personal",
    "user_name": "you@gmail.com",
    "gaia_name": "Your Name"
  },
  "Profile 3": {
    "name": "Work",
    "user_name": "you@company.com",
    "gaia_name": "Your Name"
  }
}
```

This is **canonical** — Chrome uses it to render the profile switcher. Any user who has logged into Google on a profile will have their email in `user_name`.

### Step 2 — Extract emails from open window tab titles

For each open Chrome window, iterate its tabs and look for an email pattern in the tab title. Google services always render the signed-in email in the page title:

- `"Inbox (10) - you@example.com - Gmail"`
- `"Calendar - you@example.com"`
- `"you@example.com | Drive"`
- `"Google Classroom - you@university.edu"`
- `"YouTube - you@example.com"`

ProtonMail, Fastmail, and most other webmails do the same thing. The library picks the first plausible email found (skipping `noreply@`, `support@`, etc.).

### Step 3 — Match and publish

Each window's extracted email is matched against the catalog's `user_name` field. The library returns a multi-index mapping:

```json
{
  "by_dir":   {"Default": "100000001", "Profile 3": "100000004"},
  "by_name":  {"Personal": "100000001", "Work": "100000004"},
  "by_email": {"you@gmail.com": "100000001", "you@company.com": "100000004"},
  "unknown":  {}
}
```

Any window whose email wasn't in the catalog (e.g., a Proton-only profile with no Google signin) lands in `unknown`. The library still tracks it — you can reference it by email substring.

### Step 4 — Look up windows by whatever handle is convenient

`chrome_window_for` resolves all of these in priority order:

1. Exact profile directory match (`"Default"`, `"Profile 3"`)
2. Exact display name match (`"Personal"`, `"Work"`)
3. Exact email match (`"you@gmail.com"`)
4. Substring of display name (`"Work"` matches `"Work (Client A)"`)
5. Substring of email (`"company.com"` matches `"you@company.com"`)
6. Substring of gaia name (the full name from your Google account)
7. Role alias from `~/.config/claude-mac-chrome/roles.json` if present

## Role aliases (optional)

If you want Claude to resolve semantic roles like `work` / `school` / `personal` rather than remembering your specific display names, create `~/.config/claude-mac-chrome/roles.json`:

```json
{
  "work": "Work",
  "school": "Uni",
  "personal": "Personal"
}
```

Values are passed through the same resolution logic, so they can be display names, emails, or profile dirs. This file lives entirely on your machine and is never committed to any repository.

## Complex JavaScript via Python

One-line JavaScript works through the bash CLI. For multi-line JS with quotes and regex, use Python to escape once centrally:

```python
import subprocess

def chrome_js(win_id, tab_id, js):
    js_escaped = js.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))
    cmd = f'tell application "Google Chrome" to execute (tab id "{tab_id}" of window id "{win_id}") javascript "{js_escaped}"'
    return subprocess.run(['osascript', '-e', cmd], capture_output=True, text=True).stdout.strip()
```

More patterns in [docs/patterns.md](docs/patterns.md).

## Prerequisites

**One-time setup:** enable JavaScript from Apple Events in every Chrome profile you want to automate:

**View → Developer → Allow JavaScript from Apple Events**

This is a per-profile setting. Enable it once in each profile's window. Without it, `execute ... javascript` returns `missing value` regardless of the JS itself.

## Verifying you're logged in

Login redirects are silent. A logged-out Gmail tab returns HTTP 200 with a positive-looking title but is actually the sign-in form. Verify with an authenticated-only element:

```bash
chrome_js "$WIN" "$TAB" "(!!document.querySelector('a[aria-label*=\"Google Account\"]')) + ''"
# → "true" if logged in, "false" if not
```

Per-site selectors:

| Site | Authenticated marker |
|---|---|
| Gmail | `a[aria-label*="Google Account"]` |
| ProtonMail | `[data-testid="heading:userdropdown"]` |
| GitHub | `meta[name="user-login"]` |
| LinkedIn | `.global-nav__me-photo` |
| Twitter/X | `a[href="/compose/post"]` |

## Known limitations

1. **Requires at least one Google tab (or one tab with an email in its title) per window you want to identify.** Most profiles have Gmail / Calendar / YouTube / Docs open. For fully Google-free profiles (e.g., a Proton-only work window), fall back to the `unknown` bucket and reference by email substring.
2. **`missing value` from `execute javascript`** usually means your JS returned `undefined` (wrap in `(function(){...; return foo;})()`) or Apple Events JS isn't enabled in that profile.
3. **Windows on a different macOS Space** may not appear in `every window` until they've been touched since Chrome started. Bring the missing window forward once, then `chrome-lib.sh refresh`.
4. **If Chrome is restarted, all window and tab IDs change.** The cache auto-detects this via `exists window id "..."` and re-scans.
5. **Chrome's default profile blocks CDP / remote debugging** on macOS (Apple security). This library uses AppleScript instead, running as the real user with the real cookie jar.

## When NOT to use this skill

- **Not macOS.** AppleScript is the mechanism. Linux/Windows users should look at Playwright or CDP with a throwaway profile.
- **Headless automation.** This drives your real, logged-in, visible Chrome.
- **Single-profile setups.** The simpler ordinal pattern (`window 1`) will work if you have exactly one Chrome window and never open a second.
- **DOM events interception, network interception.** Use Playwright with a fresh profile for that level of control.

## Further reading

- [docs/profile-detection.md](docs/profile-detection.md) — deep dive on the Local State format, email-extraction heuristics, edge cases, and role alias configuration
- [docs/patterns.md](docs/patterns.md) — JS injection recipes (React-safe form fill, auth checks, iframes, paste-via-Cmd+V, waiting for dynamic content, tunneling large data)
