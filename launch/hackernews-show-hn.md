# Hacker News Show HN post

**Submit page:** https://news.ycombinator.com/submit
**Post type:** Show HN with URL + text

---

## Title (80 char max — this is 76 chars)

```
Show HN: Claude-mac-chrome – Deterministic Chrome multi-profile automation
```

## URL

```
https://github.com/yolo-labz/claude-mac-chrome
```

## Text (markdown converted to plain text — HN supports basic formatting only)

```
Hi HN. I built a Claude Code plugin that solves a specific kind of Chrome automation pain on macOS: when you have multiple Chrome profiles open at once (Personal, Work, School, client-specific, etc.), every existing tool I tried silently does things in the wrong profile.

The failure mode: AppleScript addresses Chrome tabs by ordinal index (`tab 5 of window 1`). Z-order shuffles on every focus change, notification, or new tab. So `window 1` between writing your script and running it is often a *different* window — different profile, different cookies, different logged-in accounts. The JS executes against the wrong DOM, returns HTTP 200, and the tooling reports success. You discover the bug later when a form got submitted from the wrong email.

CDP doesn't fix it because Chrome blocks remote debugging on the default profile (Apple security). Playwright doesn't fix it because launching with a fresh profile loses your cookies. The Claude in Chrome extension doesn't fix it because it only runs in the browser-side agent loop, not in cron jobs.

The fix is three things stacked:

1. Chrome's own Local State file at ~/Library/Application Support/Google/Chrome/Local State is a JSON dict of every profile on the machine, with directory names, display names, and signed-in Google emails. You can read it without asking the user.

2. Every Gmail/Drive/Calendar/Classroom/ProtonMail tab title contains the signed-in email (e.g., "Inbox (10) - you@example.com - Gmail"). Walk every tab in every window, regex-extract emails, match against the catalog. Now you know which window belongs to which profile.

3. AppleScript actually supports stable string IDs for windows and tabs — `id of window w` returns "817903115" and that string persists across z-order reorders, tab reorders, focus changes, Mission Control. Direct addressing works: `execute (tab id "X" of window id "Y") javascript "..."`. Almost no tool uses this; everyone uses ordinals because that's what the tutorials show.

The interesting case is same-email profiles — say you have one Google account but separate Chrome profiles for "Personal Shopping" and "Personal Dev". Email extraction returns the same email for both. To disambiguate, the library parses each profile's binary Sessions/Tabs SNSS file (Chrome's per-profile session snapshot) via `strings`, extracts URLs, and computes set overlap with the live window's tab URLs. Whichever profile's stored URL set overlaps most with the live window wins. Ties broken by SNSS file mtime.

I tested this with a synthetic 3-profile collision: one shared Gmail, three windows with different content (Amazon/eBay vs GitHub/StackOverflow vs arxiv/Nature). All three windows routed correctly with confidence 1.000, runner-up scores capped at 0.333 (matching only the shared Gmail URL).

Deterministic. No AI needed. Zero user configuration.

The whole thing is one bash file (chrome-lib.sh, ~720 lines, shellcheck-clean, shfmt-clean) plus Python stdlib for the embedded parsing logic. No npm install, no pip install, no extension. Reads its own home directory only — no network, no telemetry.

Repo: https://github.com/yolo-labz/claude-mac-chrome
License: MIT

Happy to answer questions about the SNSS format, the AppleScript stable-ID trick, or why I went down this rabbit hole instead of just running headless Playwright like a normal person.
```

---

**Tone notes:** HN audience appreciates technical depth + honest tradeoffs. Avoid marketing speak. The "why I went down this rabbit hole" closing invites discussion. Don't include emoji or marketing badges in the body — HN strips them anyway.

**Best time to post:** Tuesday-Thursday 8-10am Pacific (peak HN traffic). Avoid weekends.
