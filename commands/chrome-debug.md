---
description: Dump the Chrome profile catalog (from Local State) and show which open windows are matched to which profiles. Use this at the start of any multi-profile Chrome automation task to confirm the library can see your profiles.
---

# /chrome-debug

Run the chrome-lib debug command and return a human-readable dump of:

1. The profile catalog from Chrome's `Local State` file (every profile on this machine, regardless of whether it's currently open)
2. The matched open windows (which window ID maps to which profile, based on email extraction from tab titles)
3. Any "unknown" windows whose emails couldn't be matched against the catalog

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh" debug
```

Expected output format:

```
Profile catalog (from Chrome Local State):
  [Default     ] Personal                    you@gmail.com
  [Profile 1   ] Study                       you@university.edu
  [Profile 3   ] Work                        you@company.com

Matched windows:
  win id=100000001  Default    Personal  you@gmail.com
  win id=100000003  Profile 1  Study     you@university.edu
  win id=100000004  Profile 3  Work      you@company.com
```

Troubleshooting:

- **Profile in catalog but not in Matched windows:** that window might be closed, on a different macOS Space, or have no email-bearing tab open. Open Gmail in it (or pin it) and re-run with `chrome-lib.sh refresh`.
- **Catalog is empty:** `Local State` file not found or corrupt. Check `~/Library/Application Support/Google/Chrome/Local State` exists.
- **Windows listed under "Unknown":** the email in the tab title doesn't match any catalog profile. Likely a Proton-only profile or a profile where Chrome hasn't been signed into Google yet.

See `${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/docs/profile-detection.md` for the full troubleshooting guide.
