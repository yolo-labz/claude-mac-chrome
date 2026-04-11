---
name: check-emails-all-profiles
description: Check unread email count across all Chrome profiles on macOS (Gmail, ProtonMail, Fastmail, Outlook). Use when the user asks to check emails, check inbox, see unread messages, or get inbox status across their Chrome profiles.
allowed-tools:
  - Bash
---

# Check Emails Across All Chrome Profiles

This skill reports the current unread email count for each Chrome profile by reading the Gmail/ProtonMail/Fastmail/Outlook tab title via the `claude-mac-chrome` plugin.

## When to use

- "check my emails"
- "how many unread do I have"
- "inbox status across profiles"
- "unread count in each profile"
- "check email in Work/Personal/Study"

## What it does

Runs `chrome-lib.sh check_inboxes` which:
1. Reads the Chrome profile catalog from Local State
2. For each profile, finds the first mail tab matching one of: `mail.google.com`, `mail.proton.me`, `app.fastmail.com`, `outlook.live.com`, `outlook.office.com`
3. Extracts the unread count from `document.title` using a provider-specific regex
4. Reports per-profile status including delta since last check

## Running the skill

```bash
chrome-lib.sh check_inboxes
```

## Output format

One structured line per profile on stdout:

```
PROFILE=<name> EMAIL=<email> UNREAD=<N> DELTA=<+/-N> STATUS=<status>
```

Where `STATUS` is one of:
- `ok` — unread count successfully read
- `window_not_found` — profile has no open Chrome window
- `tab_not_found` — no mail tab open in this profile
- `js_error` — tab found but `document.title` read failed
- `rate_capped` — JS injection rate limit (50 calls/invocation) hit

## How to present results

After running the command, summarize the results in natural language. For example:

> You have 12 unread in Personal (+3 since last check), 5 in Work (same as before), and Study profile shows 0. The UFPE profile window wasn't open.

**Always report successes first, then list any failures (window_not_found, tab_not_found, js_error) separately.** Never omit a failure — the user needs to know their Work profile window was closed, not just that Work is missing from the summary.

If all profiles show `STATUS=js_error` or `STATUS=tab_not_found`, suggest the user open their mail tabs and try again.

## Security note

Unread counts come from `document.title`, which is untrusted page data. A malicious page could spoof its title to report fake counts. This is acceptable for informational display but MUST NOT be used for security decisions.

## Plugin requirements

- `claude-mac-chrome` plugin installed (`/plugin marketplace add yolo-labz/claude-mac-chrome`)
- Chrome must be running
- `jq` installed (`brew install jq`)
- Apple Events permission granted to Terminal (one-time macOS prompt)
