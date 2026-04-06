# Profile Detection — Reference Guide

`chrome-lib.sh` identifies each open Chrome window by combining two authoritative, user-agnostic sources:

1. **Chrome's own `Local State` file** — the catalog of every profile on the machine
2. **Email addresses embedded in tab titles** — the per-window signal of which profile is which

This is deterministic, requires zero user configuration, and works on any macOS Chrome setup out of the box.

## The Local State file

**Location:** `~/Library/Application Support/Google/Chrome/Local State`

It's a JSON file that Chrome itself reads and writes. You can look at it safely — no modification needed. The relevant section is `profile.info_cache`:

```json
{
  "profile": {
    "info_cache": {
      "Default": {
        "name": "Personal",
        "user_name": "you@gmail.com",
        "gaia_name": "Your Name",
        "is_ephemeral": false
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

Each key is a **profile directory name** — the actual folder under `~/Library/Application Support/Google/Chrome/` where that profile's cookies, history, and preferences live. Chrome's UI shows the `name` field in the profile switcher; `user_name` is the signed-in Google account; `gaia_name` is the full name from that Google account.

Chrome names profiles `Default`, `Profile 1`, `Profile 2`, ... in order of creation. The first profile is always `Default`. Deleted profiles leave gaps — if you created 3 profiles and deleted Profile 2, you'll see `Default`, `Profile 1`, `Profile 3`.

### Reading it yourself

```python
import json, os

with open(os.path.expanduser("~/Library/Application Support/Google/Chrome/Local State")) as f:
    state = json.load(f)

for dir_name, meta in state["profile"]["info_cache"].items():
    print(f"{dir_name:12s} → {meta.get('name', '?'):20s} ({meta.get('user_name', 'no google account')})")
```

Or via the library:

```bash
chrome-lib.sh catalog | python3 -m json.tool
```

### Edge cases

- **No Google account in a profile.** The `user_name` field is empty string. The profile still exists in the catalog but won't be matched by email extraction (step 2 below). Reference it by display name or directory instead.
- **Multiple Google accounts in one profile.** Chrome only tracks the *primary* (first-added) account in `user_name`. Switching between multiple signed-in accounts in the same profile doesn't change the Local State.
- **Ephemeral / guest profiles.** These have `is_ephemeral: true` and are skipped in most UI contexts. The library still returns them in the catalog — it's up to the caller to filter.

## Email extraction from tab titles

Google services and most webmails render the signed-in account email in the page title. Examples seen in the wild:

| Service | Title pattern |
|---|---|
| Gmail | `"Inbox (10) - you@example.com - Gmail"` |
| Google Drive | `"you@example.com - Google Drive"` |
| Google Classroom | `"Google Classroom - you@university.edu"` |
| ProtonMail | `"Inbox | you@proton.me | Proton Mail"` |
| Fastmail | `"Inbox • you@fastmail.com"` |

The library looks for the pattern `/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/` in every tab title and picks the first match that isn't a known automated sender (`noreply@`, `support@`, `mailer@`, etc.). It prefers matches that exactly equal a catalog email over generic matches.

### Ensuring reliable detection per window

For the library to match a window to its profile, **at least one tab in that window** must satisfy one of:

1. **Gmail open** — easiest; the signed-in email is always in the tab title
2. **ProtonMail open** — same
3. **Google Drive open** — email in title
4. **Google Classroom open** — email in title
5. **A custom tab whose title contains a catalog email** — you can pin one yourself

**Pragmatic recommendation:** pin Gmail in every Chrome profile. This is what most multi-profile users do anyway (the whole reason to have multiple profiles is usually to separate email identities). Once pinned, detection is automatic forever.

### Windows that can't be matched

If a window has no email-in-title tab at all, the library's email extraction returns nothing and the window doesn't appear in the `by_dir` / `by_name` / `by_email` indexes. Three fallbacks:

1. **Open Gmail in that window** — navigate any tab to `https://gmail.com` and let it authenticate
2. **Define a role alias** with a display-name or profile-directory reference (see below)
3. **Reference by profile directory directly** — `chrome_window_for "Profile 3"` still works if you know the directory, even without email matching

## Role aliases (optional)

Role aliases let Claude use semantic names like `work` / `school` / `personal` without hardcoding your specific profile display names into automation scripts. This is useful when you want to share automation with teammates who have different profile names.

Create `~/.config/claude-mac-chrome/roles.json`:

```json
{
  "work": "Acme Corp",
  "school": "Student",
  "personal": "Personal",
  "client-a": "you@client-a.com",
  "client-b": "Profile 4"
}
```

Values can be any reference that `chrome_window_for` accepts (profile directory, display name, email, or substring of any of those). The file is:

- Stored in your XDG config dir (outside the plugin install directory)
- Never committed to any repository
- Optional — the library works without it
- User-local only

### Example

Suppose your script says:

```bash
WIN=$(chrome_window_for work)
```

The resolver first checks if `"work"` is a profile dir (it's not), then a display name (it's not), then an email (it's not), then a substring of any display name (no match in default catalog). If none match, it checks `~/.config/claude-mac-chrome/roles.json`, finds `"work": "Acme Corp"`, and resolves `"Acme Corp"` as a substring of the profile display name `"Work | Acme Corp"`, returning that window's ID.

## Troubleshooting

### `chrome-lib.sh debug` shows fewer windows than I have open

Possible causes, in order of likelihood:

1. **A window is on a different macOS Space and hasn't been touched since Chrome started.** Bring it forward (Mission Control, `Cmd+Tab`, or click its dock icon), then `chrome-lib.sh refresh`.
2. **A window has no email-bearing tab.** Open Gmail (or ProtonMail, or any tab whose title contains a catalog email) in it.
3. **Chrome was restarted since the cache was last written.** Force refresh: `chrome-lib.sh refresh`.

### `window_for "work"` returns empty string

1. Is the Work profile actually open? `chrome-lib.sh debug` should list it under "Matched windows".
2. If listed but your reference doesn't match, try a different reference: exact display name, email, or profile directory.
3. If not listed, check if Gmail (or another email-bearing tab) is open in that window.
4. If you have a role alias file, check its syntax: `python3 -c "import json; print(json.load(open('$HOME/.config/claude-mac-chrome/roles.json')))"`.

### Catalog is empty

Check that `~/Library/Application Support/Google/Chrome/Local State` exists and is readable. On a fresh Chrome install with no profiles configured, `info_cache` may be empty — open Chrome, create at least one profile, sign into Google, and the catalog will populate.

### Email extraction matches the wrong email

If a tab title happens to contain someone else's email (e.g., a Gmail thread with another user's email in the subject), the library might pick it up. The library prefers exact catalog matches over arbitrary matches, so as long as the window has at least one tab with a signed-in catalog email, it'll choose correctly. If you see mis-matches, pin a Gmail tab in that window to guarantee the primary-account email is always present.

## Security and privacy notes

- The library reads the local user's `Local State` file, which contains email addresses and profile names. This data **never leaves your machine** — it's used only to build an in-memory mapping and optionally cached at `/tmp/chrome-fingerprint.json`.
- No network calls.
- No telemetry.
- `/tmp/chrome-fingerprint.json` contains your profile emails and display names. If you're on a shared machine, set `TMPDIR` to a private location before sourcing the library, or clear the cache (`chrome-lib.sh refresh` then `rm /tmp/chrome-fingerprint.json`) after use.
