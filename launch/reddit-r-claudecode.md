# Reddit r/ClaudeCode launch post

**Subreddit:** [r/ClaudeCode](https://www.reddit.com/r/ClaudeCode/submit)
**Post type:** Link post (with self-text body) — paste the URL in the link field, then expand body via "Add text"

---

## Title (300 char max — this is 124 chars)

```
Show: claude-mac-chrome — deterministic Chrome multi-profile automation for Claude Code on macOS (zero deps, AppleScript)
```

## Link

```
https://github.com/yolo-labz/claude-mac-chrome
```

## Body

```markdown
**TL;DR:** A zero-dependency Claude Code plugin that drives Chrome on macOS across multiple profiles (Personal/Work/School/etc.) without the wrong-profile drift bug that bites every existing tool. Uses Chrome's own Local State catalog + tab-title email extraction + same-email disambiguation via SNSS Sessions/Tabs URL-set overlap. Stable AppleScript IDs throughout. shellcheck + shfmt clean.

## The problem

If you have multiple Chrome profiles open on macOS and you ask Claude Code to drive Gmail in your Work profile, every existing tool I tried silently breaks the same way:

1. AppleScript address `tab 5 of window 1` resolves to a window that's currently in front
2. Z-order shuffles between the time the script is written and run (a notification fires, you Cmd-Tab away, a new tab is created)
3. `window 1` is now a *different* Chrome window — different profile, different cookies, different account
4. The JS executes successfully against the wrong DOM, returns HTTP 200, and Claude reports success
5. You only discover it later when a form got submitted from the wrong email

Existing tools either hardcode ordinal indices (`obra/superpowers-chrome` uses CDP which Chrome blocks on the default profile; `SpillwaveSolutions/automating-chrome` uses JXA but with `chrome.windows[0].tabs[0]`-style ordinals), or they ask you to hand-configure URL fingerprints per profile (which leaks personal infrastructure into the codebase). Neither is acceptable.

## The fix

Three insights stacked together:

**1. Chrome's own Local State file is an authoritative profile catalog.** At `~/Library/Application Support/Google/Chrome/Local State`, Chrome maintains a JSON dict of every profile on the machine — directory name, display name, signed-in Google account email, gaia name. You can read it. You don't need to ask the user.

**2. Tab titles contain the signed-in email.** Every Gmail tab is `"Inbox (N) - you@example.com - Gmail"`. Same for Drive, Calendar, Classroom, ProtonMail, Fastmail. Walk every tab in every window, regex-extract emails, match against the catalog → done. No URL fingerprints, no user config.

**3. AppleScript window/tab IDs are stable.** This is the part nobody seems to use. `id of window w` returns `"817903115"`, and that string is stable across z-order reorders, tab reorders, focus changes, Mission Control swipes — anything except a Chrome restart. AppleScript also supports direct addressing: `execute (tab id "X" of window id "Y") javascript "..."`. So once you've matched windows to profiles, you address by ID forever and the drift problem evaporates.

## The interesting part — same-email disambiguation

What if two profiles share the same Google account? E.g., one email but separate profiles for Personal Shopping vs Personal Dev vs Personal Research. The Local State catalog has both profiles with the same `user_name`. Email extraction can't tell them apart.

The fix: Chrome writes a binary `Sessions/Tabs_<id>` SNSS file per profile, updated in near-real-time, containing the URLs of every tab the profile currently has open. Run `strings` over it, regex-extract URLs, compute set overlap with the live window's tab URLs. The profile whose stored URL set overlaps most with the live window wins. Ties broken by file mtime.

I tested this with a synthetic 3-profile collision (one shared Gmail, one for shopping, one for dev, one for research): all three windows correctly routed with confidence 1.000, runner-up scores capped at 0.333 (matching only the shared Gmail URL).

Deterministic. No AI needed. No user config.

## Install

```
/plugin marketplace add yolo-labz/claude-mac-chrome
/plugin install claude-mac-chrome@claude-mac-chrome
```

Or clone and use directly:
```
git clone https://github.com/yolo-labz/claude-mac-chrome.git
source claude-mac-chrome/skills/chrome-multi-profile/chrome-lib.sh
WIN=$(chrome_window_for "Work")
TAB=$(chrome_tab_for_url "$WIN" "mail.google.com")
chrome_js "$WIN" "$TAB" "document.title"
```

## What's in the box

- **`chrome-lib.sh`** — pure bash + osascript + python3 stdlib, 720 lines, shellcheck-clean (style severity), shfmt-clean
- **Local State parser** — reads Chrome's authoritative profile catalog
- **SNSS URL extractor** — strings-based parser of Chrome's per-profile Sessions/Tabs files
- **Stable-ID addressing** — `id of window` / `id of tab` direct addressing throughout
- **Auto-cache + invalidation** — `/tmp/chrome-fingerprint.json` with `exists window id "..."` staleness check
- **Optional role aliases** — `~/.config/claude-mac-chrome/roles.json` maps semantic names like `work`/`personal` to specific profiles, never committed to any repo
- **`/chrome-debug` slash command** — human-readable diagnostic
- **`scripts/lint.sh`** — shellcheck + shfmt + live smoke test, auto-fetches tools via `nix run nixpkgs#<pkg>` if not in PATH

## Limitations

- **macOS only.** AppleScript is the mechanism.
- **Requires "Allow JavaScript from Apple Events" per profile** (one-time toggle in View → Developer).
- **Not headless** — this is for driving your real, logged-in, visible Chrome.
- **Email-bearing tab needed per profile** — Gmail, ProtonMail, or any tab with an email in its title. Pin Gmail in each profile and it's bulletproof.

## Source

https://github.com/yolo-labz/claude-mac-chrome — MIT license, v1.0.0-rc1

Happy to answer questions or take PRs. The same-email SNSS approach was the part I was most uncertain about until I built the synthetic test — turned out clean.
```

---

**After posting:** I'd suggest cross-posting to r/ClaudeAI as well for additional reach. Same body, slightly tweaked title.
