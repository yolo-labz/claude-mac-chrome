# Twitter / X thread

**Post type:** Thread (~7 tweets)
**Add at the end of each tweet:** `1/7`, `2/7`, etc., or use the auto-numbering if posting via the web composer

---

## Tweet 1/7 (the hook — 280 chars max, this is 277)

```
Built a Claude Code plugin that drives Chrome on macOS across multiple profiles without the wrong-profile drift bug.

Zero deps, zero user config, deterministic.

Uses Chrome's own Local State catalog + tab-title email extraction + SNSS URL overlap.

🧵 How it works ↓
```

## Tweet 2/7 (the problem — 277 chars)

```
The bug: AppleScript addresses Chrome via `tab 5 of window 1`. Z-order reshuffles on every focus change. So `window 1` between writing your script and running it is often a *different* window, different profile, different cookies.

Forms get sent from the wrong email. Silently.
```

## Tweet 3/7 (why obvious fixes fail — 280 chars)

```
Why the obvious fixes don't work:

• Playwright → fresh profile, no cookies
• CDP → Chrome blocks it on the default profile (Apple security)
• Extension → only runs in browser agent loop, not CLI cron jobs
• Hardcoded URL fingerprints → leaks personal infra, ambiguous matches
```

## Tweet 4/7 (signal 1+2 — 278 chars)

```
The fix is 3 signals stacked.

Signal 1: Chrome's own Local State file at ~/Library/Application Support/Google/Chrome/Local State has an authoritative catalog of every profile + signed-in Google email.

Signal 2: Every Gmail/Drive/Classroom tab title contains the email. Regex it.
```

## Tweet 5/7 (signal 3 — 280 chars)

```
Signal 3: AppleScript exposes STABLE STRING IDs for windows and tabs that nobody uses.

`id of window w` → "817903115" — persists across z-order reorders, tab reorders, focus changes.

Address directly: `execute (tab id "X" of window id "Y") javascript "..."`. Drift gone.
```

## Tweet 6/7 (signal 4 — 280 chars)

```
What if 2 profiles share the same Google account? E.g., one Gmail but separate profiles for shopping vs dev.

Signal 4: each profile has its own Sessions/Tabs SNSS file. Run `strings`, regex URLs, compute set overlap with the live window.

Synthetic test: 3 profiles, 100% routing.
```

## Tweet 7/7 (CTA — 273 chars)

```
720 lines of bash, shellcheck + shfmt clean, MIT.

Repo: github.com/yolo-labz/claude-mac-chrome

Install in Claude Code:
/plugin marketplace add yolo-labz/claude-mac-chrome
/plugin install claude-mac-chrome@claude-mac-chrome

Happy to take feedback, PRs, real-world same-email tests.
```

---

## Posting notes

- Use the web composer at https://x.com/compose/post for thread formatting (auto-handles numbering and reply-to-self chaining)
- Add a screenshot of `chrome-lib.sh debug` output to tweet 1 or 7 for the visual hook
- Tag handles to consider: `@AnthropicAI` (carefully — don't beg), `@AnthropicCode`, `@simonw` (he covers terminal AI tools well)
- Best time: weekday morning Pacific
