---
title: "How I solved Chrome multi-profile drift in Claude Code automation on macOS"
description: "A technical deep dive into deterministic Chrome profile detection using Local State, tab title email extraction, and SNSS Sessions/Tabs URL-set overlap — without ordinal indices, CDP, or fresh profiles."
canonical_url: https://github.com/yolo-labz/claude-mac-chrome
tags: claudecode, chrome, applescript, macos
published: false
---

# How I solved Chrome multi-profile drift in Claude Code automation on macOS

If you've ever asked Claude Code to drive Chrome on macOS while you have multiple profiles open — Personal, Work, School, a client-specific one — you've probably hit this bug: the automation runs successfully, returns HTTP 200 with a plausible-looking page title, and silently does the thing in **the wrong profile**. Form submitted from the wrong email. Comment posted under the wrong identity. Cart added to the wrong account.

I spent a chunk of an afternoon chasing this and ended up building [claude-mac-chrome](https://github.com/yolo-labz/claude-mac-chrome) — a small Claude Code plugin that fixes the root cause deterministically with zero user configuration. This post is the technical explanation of what I found and why the standard approaches don't work.

## The shape of the bug

The Chrome scripting bridge on macOS lets you address windows and tabs by ordinal index:

```applescript
tell application "Google Chrome"
  execute tab 5 of window 1 javascript "document.title"
end tell
```

This is what every tutorial shows. It's also what every Claude Code Chrome plugin I looked at uses internally — `obra/superpowers-chrome` (CDP-based), `SpillwaveSolutions/automating-chrome` (JXA-based), `prasmussen/chrome-cli` (the classic). The problem: **`window 1` reflects Z-order, not stable identity**. Whenever any window comes to the front — because a notification appeared, because you Cmd-Tabbed to a different app, because Chrome itself decided to bring a window forward — Chrome reorders. By the time your AppleScript dispatches, `window 1` is the most-recently-frontmost window, which is often *not* the one your script was written for.

Same for tab indices. `tab 5` shifts every time a tab is opened, closed, or reordered.

The failure is invisible: the wrong tab loads, the wrong DOM is queried, the wrong cookies are sent. AppleScript returns success because the call technically succeeded against *some* tab. There's no error. You discover the bug later when a form was submitted from the wrong email account.

## Why the obvious fixes don't work

**"Just use Playwright."** Playwright launches a fresh Chrome profile with no cookies, so it can't access your logged-in sessions. Useless for the "drive my logged-in Gmail in the Work profile" use case.

**"Just use Chrome DevTools Protocol."** Chrome blocks CDP on the default profile by Apple security policy. `chrome --remote-debugging-port=9222` silently refuses to expose a debugger when launched against the default user data directory. You can work around this by relaunching with a fresh profile, but again — no cookies.

**"Just use the Claude in Chrome extension."** It only runs in the browser-side agent loop, not in Claude Code CLI sessions. Doesn't help cron jobs or overnight automation.

**"Just hardcode URL fingerprints per profile."** This is what some tools recommend: pin a unique URL in each profile and match by substring. It works, but it leaks personal infrastructure into your code (your self-hosted dashboard URL, your corporate intranet, your university Classroom). And it requires the user to maintain the fingerprint list. Plus the same URL might be pinned in multiple profiles, leading to ambiguous matches.

**"Just use ps aux to find profiles by --profile-directory flag."** Doesn't work on macOS — Chrome runs as a single main process for all profiles. Helper processes have the flag, but mapping helper PIDs to specific windows is unreliable.

**"Just use accessibility API to read the Chrome profile button."** Requires TCC accessibility permission for the calling process (Terminal, iTerm, the Claude Code CLI, etc.) — a one-time grant the user has to make manually. And the Chrome custom Cocoa drawing is brittle to read across versions.

## The actual fix — three signals stacked

After ruling all of those out, I found three deterministic signals that combine cleanly:

### Signal 1: Chrome's own Local State catalog

Chrome maintains a JSON file at `~/Library/Application Support/Google/Chrome/Local State` that's the authoritative catalog of every profile on the machine. The relevant section is `profile.info_cache`:

```json
{
  "profile": {
    "info_cache": {
      "Default": {
        "name": "Personal",
        "user_name": "you@gmail.com",
        "gaia_name": "Your Name"
      },
      "Profile 1": {
        "name": "Study",
        "user_name": "you@university.edu"
      },
      "Profile 3": {
        "name": "Work",
        "user_name": "you@company.com"
      }
    }
  }
}
```

This is canonical. Chrome's own UI reads it for the profile switcher. You don't need to ask the user. You just read it.

```python
import json, os
with open(os.path.expanduser("~/Library/Application Support/Google/Chrome/Local State")) as f:
    state = json.load(f)
for dir_name, meta in state["profile"]["info_cache"].items():
    print(f"{dir_name}: {meta['name']} ({meta.get('user_name', '(no Google account)')})")
```

### Signal 2: Tab titles contain the signed-in email

This is the part I almost missed. Every Google service renders the signed-in email in the page title:

| Service | Title pattern |
|---|---|
| Gmail | `Inbox (10) - you@example.com - Gmail` |
| Drive | `you@example.com - Google Drive` |
| Classroom | `Google Classroom - you@university.edu` |
| ProtonMail | `Inbox \| you@proton.me \| Proton Mail` |
| Fastmail | `Inbox • you@fastmail.com` |

Walk every tab in every Chrome window via AppleScript, extract emails via regex, match against the catalog. Now every window has a profile assignment.

```python
import re
EMAIL_RE = re.compile(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+')
for tab_title in tab_titles:
    for m in EMAIL_RE.finditer(tab_title):
        em = m.group(0).lower()
        if em in catalog_emails:
            return catalog_emails[em]  # the profile_dir
```

### Signal 3: Stable AppleScript window/tab IDs

Here's the bit that nobody seems to use. AppleScript exposes **stable string IDs** for both windows and tabs:

```applescript
tell application "Google Chrome"
  set wid to id of window 1
  -- "817903115" — persists across z-order reorders
  set tid to id of tab 5 of window 1
  -- "817903235" — persists across tab reorders
end tell
```

These IDs are:
- **Stable across z-order reorders** — the window can come and go from the front and the ID stays the same
- **Stable across tab reorders** — opening, closing, dragging tabs doesn't change them
- **Stable across focus changes** — clicking around doesn't change them
- **Reset only when Chrome restarts** — at which point a single re-scan fixes everything

And — this is the part I had to actually test to believe — **AppleScript supports direct addressing by these IDs**:

```applescript
tell application "Google Chrome"
  set t to execute (tab id "817903235" of window id "817903115") javascript "document.title"
  set URL of (tab id "817903235" of window id "817903115") to "https://example.com"
end tell
```

Once you've matched a window to a profile via signals 1 and 2, you remember the stable IDs and address them directly forever. The drift problem completely disappears.

## The hard case — same email, multiple profiles

The setup so far works perfectly when each profile has a different signed-in email. But what about the case where one Google account has multiple Chrome profiles? Maybe one for "Personal Shopping" and one for "Personal Dev" and one for "Personal Research" — same `you@gmail.com` everywhere. Email extraction returns the same email for all three windows. Local State has all three profiles with the same `user_name`. The email→profile_dir map collides.

Time for signal 4.

### Signal 4: SNSS Sessions/Tabs URL-set overlap

Each Chrome profile writes its own binary `Sessions/Tabs_<id>` file at `~/Library/Application Support/Google/Chrome/<profile_dir>/Sessions/Tabs_<id>`. This is the SNSS (Session Sync Storage) format Chrome uses for its session restore feature. It contains every URL the profile currently has open as part of the serialized session.

You can extract URLs from it without parsing the binary format — just `strings`-style printable extraction + a URL regex:

```python
def extract_urls_from_snss(path):
    with open(path, "rb") as f:
        data = f.read()
    urls = set()
    for chunk in re.findall(rb'[\x20-\x7e]{8,}', data):
        s = chunk.decode("ascii", errors="ignore")
        for m in re.finditer(r'https?://[^\s<>"\'\\`^{}|]+', s):
            urls.add(m.group(0).rstrip(',.);]'))
    return urls
```

Now the disambiguation algorithm: for each window with an ambiguous email match, score each candidate profile by **A-coverage** — how much of the window's live URL set is also in the profile's stored URL set. The profile with the highest score wins. Ties broken by SNSS file mtime (most recently written = currently being interacted with).

```python
def url_overlap_score(window_urls, profile_urls):
    if not window_urls:
        return 0.0
    return len(window_urls & profile_urls) / len(window_urls)
```

I validated this with a synthetic test: 3 profiles all signed into `same@gmail.com`, three windows with disjoint content (Amazon/eBay vs GitHub/StackOverflow vs arxiv/Nature). All three windows routed to the correct profile with confidence 1.000. Runner-up scores topped out at 0.333 (matching only the shared Gmail URL that every window has open).

Deterministic. No AI needed. No user configuration.

## Putting it all together

The full pipeline:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Read Local State → catalog {profile_dir: {name, email}}      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│ 2. For each open Chrome window via AppleScript:                  │
│      - iterate tabs                                              │
│      - extract emails from tab titles                            │
│      - collect URL set                                           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│ 3. Try email → profile match                                     │
│      if exactly 1 profile → ASSIGN (method=email_unique)         │
│      if 0 profiles → step 4 with all candidates                  │
│      if 2+ profiles → step 4 with email-matching candidates      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│ 4. Read each candidate profile's Sessions/Tabs_<latest> SNSS     │
│    file via `strings`, extract URLs                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│ 5. Score each candidate by URL overlap; highest wins, ties      │
│    broken by SNSS file mtime                                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│ 6. ASSIGN window → profile, address by stable IDs forever       │
└─────────────────────────────────────────────────────────────────┘
```

The whole library is 720 lines of bash + embedded Python (stdlib only, no pip install), plus a 141-line lint script that runs shfmt + shellcheck + a live Chrome smoke test. shellcheck-clean at `--severity=style`. shfmt-clean. Zero npm, zero pip, zero homebrew prerequisites.

## What this is not

- **Not headless** — this drives your real, logged-in, visible Chrome. Use Playwright for headless.
- **Not cross-platform** — macOS only. AppleScript is the mechanism.
- **Not a CDP wrapper** — explicitly avoids CDP because it's blocked on the default profile.
- **Not an extension** — runs as the real user via Apple Events, no extension install.
- **Not for DOM event interception or network interception** — for that level of control, use Playwright with a throwaway profile.

## Try it

```bash
# In Claude Code:
/plugin marketplace add yolo-labz/claude-mac-chrome
/plugin install claude-mac-chrome@claude-mac-chrome
```

Or directly:

```bash
git clone https://github.com/yolo-labz/claude-mac-chrome.git
cd claude-mac-chrome
./skills/chrome-multi-profile/chrome-lib.sh debug
```

You'll see your full profile catalog and which windows are matched to which profiles. Then:

```bash
LIB="./skills/chrome-multi-profile/chrome-lib.sh"
WIN=$($LIB window_for "Work")              # match by display name substring
TAB=$($LIB tab_for_url "$WIN" "mail.google.com")
$LIB js "$WIN" "$TAB" "document.title"
```

## What I'd change

If I were starting fresh:

- **A native messaging companion extension** would let me read the actual currently-loaded profile from inside Chrome via `chrome.identity.getProfileUserInfo()`, without needing Apple Events JS or the Local State parsing trick. But that requires installing an extension per profile, which is friction.
- **A SQLite reader for `History`** would give me historical visit data per profile in addition to the SNSS current-session data, useful for an additional disambiguation signal. But Chrome locks the History DB while the profile is loaded, so I'd need to copy it first.
- **An AI fallback** — for the truly pathological case where two profiles have identical tab sets (unlikely but possible), the SNSS scoring returns a tie. A small LLM call could classify by intent ("this window is for shopping vs research"). I left this out of v0.3.0 because the deterministic mtime tiebreaker handles all the realistic cases I've tested.

## Source

[github.com/yolo-labz/claude-mac-chrome](https://github.com/yolo-labz/claude-mac-chrome) — MIT license, 0.3.0

If you have a same-email multi-profile setup and want to test the disambiguation, I'd love a PR with a real-world validation. The synthetic test passed but real-world data is always more interesting.
