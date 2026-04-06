#!/bin/bash
# chrome-lib.sh — Chrome automation using authoritative profile catalog + stable IDs
#
# Key techniques (empirically verified on macOS Sequoia / Chrome 146.x, April 2026):
#
#   1. Chrome's Local State file at
#        ~/Library/Application Support/Google/Chrome/Local State
#      contains an authoritative `profile.info_cache` dictionary mapping profile
#      directory names (Default, Profile 1, Profile 3, ...) to their display
#      name, signed-in Google account email, and gaia name. This is the canonical
#      source of truth for "what profiles exist on this machine."
#
#   2. Every Chrome tab's `title` includes the signed-in account email whenever
#      the tab is any Google service (Gmail, Calendar, Drive, Docs, YouTube,
#      Classroom, etc.) or any mail client (ProtonMail, Fastmail). We extract the
#      first email found in any tab's title to identify which window belongs to
#      which profile in the catalog.
#
#   3. AppleScript exposes STABLE STRING IDs for both windows and tabs:
#        id of window w    → "100000001"   persists across z-order reorders
#        id of tab t of window w → "100000002"   persists across tab reorders
#      Direct addressing by these IDs works:
#        execute (tab id "X" of window id "Y") javascript "..."
#
# Combining (1) + (2) + (3) gives us: "open Gmail in the Work profile" resolves to
# a stable tab ID in a stable window ID, with zero z-order drift and zero tab
# index drift. No user configuration needed — the library reads the local user's
# own Chrome profiles and matches them against the user's own running windows.
#
# =============================================================================
# Usage (CLI mode)
# =============================================================================
#
#   chrome-lib.sh catalog          # dump profile catalog from Local State
#   chrome-lib.sh fingerprint      # dump {profile_dir: window_id} mapping
#   chrome-lib.sh debug            # human-readable table
#
#   WIN=$(chrome-lib.sh window_for "Acme Corp")   # by display-name substring
#   WIN=$(chrome-lib.sh window_for "you@gmail.com")  # by email
#   WIN=$(chrome-lib.sh window_for "Profile 3")  # by profile directory
#
#   TAB=$(chrome-lib.sh tab_for_url "$WIN" "mail.google.com")
#   chrome-lib.sh js "$WIN" "$TAB" "document.title"
#   chrome-lib.sh navigate "$WIN" "$TAB" "https://example.com"
#   NEW=$(chrome-lib.sh new_tab "$WIN" "https://example.com")
#   chrome-lib.sh tab_url "$WIN" "$TAB"
#   chrome-lib.sh refresh          # invalidate cache
#
# =============================================================================
# Usage (source into your script)
# =============================================================================
#
#   source "${CLAUDE_PLUGIN_ROOT}/skills/chrome-multi-profile/chrome-lib.sh"
#   WIN=$(chrome_window_for work)
#   TAB=$(chrome_tab_for_url "$WIN" "mail.google.com")
#   chrome_js "$WIN" "$TAB" "document.title"
#
# =============================================================================
# Role aliases (optional)
# =============================================================================
#
# If you maintain a local config file at ~/.config/claude-mac-chrome/roles.json:
#
#   { "work": "Work", "school": "Uni", "personal": "Personal" }
#
# …then chrome-lib.sh resolves `window_for work` to the window whose profile
# display name contains "Work". The config file is NEVER committed to any
# repository, contains no personal info the user hasn't explicitly chosen to put
# there, and is entirely optional.

CHROME_USER_DATA="${CHROME_USER_DATA_DIR:-$HOME/Library/Application Support/Google/Chrome}"
CHROME_LOCAL_STATE="$CHROME_USER_DATA/Local State"
CHROME_CACHE="/tmp/chrome-fingerprint.json"
CHROME_ROLES_FILE="${CHROME_ROLES_FILE:-$HOME/.config/claude-mac-chrome/roles.json}"

# ---------------------------------------------------------------------------
# Tier 1 — Authoritative profile catalog from Chrome's own Local State file
# ---------------------------------------------------------------------------
# Returns JSON: {"Default":{"dir":"Default","name":"Personal","user_name":"you@example.com",...},...}
chrome_profiles_catalog() {
  LOCAL_STATE="$CHROME_LOCAL_STATE" python3 <<'PYEOF'
import json, os, sys
p = os.environ["LOCAL_STATE"]
if not os.path.exists(p):
    sys.stderr.write(f"error: Chrome Local State not found at {p}\n")
    print("{}")
    sys.exit(0)
try:
    with open(p) as f:
        d = json.load(f)
except Exception as e:
    sys.stderr.write(f"error: failed to parse Local State: {e}\n")
    print("{}")
    sys.exit(0)
info = d.get("profile", {}).get("info_cache", {})
out = {}
for dir_name, meta in info.items():
    out[dir_name] = {
        "dir": dir_name,
        "name": meta.get("name", "") or dir_name,
        "user_name": (meta.get("user_name") or "").lower(),
        "gaia_name": meta.get("gaia_name", "") or "",
        "is_ephemeral": bool(meta.get("is_ephemeral", False)),
    }
print(json.dumps(out, ensure_ascii=False))
PYEOF
}

# ---------------------------------------------------------------------------
# Tier 2 — Raw window/tab dump via AppleScript
# ---------------------------------------------------------------------------
# Output format (tab-delimited, one row per tab):
#   window_id \t tab_id \t title \t url
chrome_windows_raw() {
  osascript <<'APPLESCRIPT'
tell application "Google Chrome"
  set out to ""
  repeat with w in windows
    set wid to id of w
    repeat with t in tabs of w
      try
        set ttl to title of t
      on error
        set ttl to ""
      end try
      try
        set u to URL of t
      on error
        set u to ""
      end try
      set out to out & wid & "	" & (id of t) & "	" & ttl & "	" & u & linefeed
    end repeat
  end repeat
  return out
end tell
APPLESCRIPT
}

# ---------------------------------------------------------------------------
# Core fingerprint — combine catalog + windows → map of profile → window_id
# ---------------------------------------------------------------------------
# Output JSON shape:
#   {
#     "by_dir":   {"Default": "100000001", "Profile 1": "100000003"},
#     "by_name":  {"Personal | Default": "100000001", "Study | Uni": "100000003"},
#     "by_email": {"you@gmail.com": "100000001", "you@university.edu": "100000003"},
#     "unknown":  {"unmatched-email@x.com": "100000099"}
#   }
chrome_fingerprint() {
  local catalog_json windows_raw
  catalog_json=$(chrome_profiles_catalog)
  windows_raw=$(chrome_windows_raw)
  CATALOG="$catalog_json" RAW="$windows_raw" python3 <<'PYEOF'
import json, os, re, sys
catalog = json.loads(os.environ.get("CATALOG", "{}"))
raw = os.environ.get("RAW", "")

# Build email → profile_dir map
email_to_dir = {v["user_name"]: k for k, v in catalog.items() if v.get("user_name")}

# Parse windows_raw, collect the first plausible email in each window's tab titles.
# Prefer emails that match the catalog exactly.
window_emails = {}  # wid -> (email, matched_in_catalog)
EMAIL_RE = re.compile(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+')
IGNORED_PREFIXES = ("noreply", "no-reply", "support", "info", "hello", "mailer", "notifications")

for line in raw.split("\n"):
    if not line.strip():
        continue
    parts = line.split("\t", 3)
    if len(parts) < 4:
        continue
    wid, tid, title, url = parts
    title_l = title.lower()
    # Pass 1: exact catalog match (highest confidence)
    found = None
    for email in email_to_dir:
        if email in title_l:
            found = (email, True)
            break
    # Pass 2: any email pattern (fallback, unknown profile)
    if not found:
        m = EMAIL_RE.search(title)
        if m:
            em = m.group(0).lower()
            if not any(em.startswith(p) for p in IGNORED_PREFIXES):
                found = (em, em in email_to_dir)
    if found:
        existing = window_emails.get(wid)
        # Upgrade unknown matches to known catalog matches if we find one later
        if existing is None or (found[1] and not existing[1]):
            window_emails[wid] = found

by_dir = {}
by_name = {}
by_email = {}
unknown = {}
for wid, (email, matched) in window_emails.items():
    if matched and email in email_to_dir:
        dir_name = email_to_dir[email]
        by_dir[dir_name] = wid
        by_name[catalog[dir_name].get("name") or dir_name] = wid
        by_email[email] = wid
    else:
        unknown[email] = wid

result = {
    "by_dir": by_dir,
    "by_name": by_name,
    "by_email": by_email,
    "unknown": unknown,
    "catalog": catalog,
}
print(json.dumps(result, ensure_ascii=False))
PYEOF
}

# ---------------------------------------------------------------------------
# Cached fingerprint (auto-refresh on stale window ID)
# ---------------------------------------------------------------------------
chrome_fingerprint_cached() {
  local need_refresh=0
  if [ ! -s "$CHROME_CACHE" ]; then
    need_refresh=1
  else
    local sample_id
    sample_id=$(python3 -c "
import json, sys
try:
    d = json.load(open('$CHROME_CACHE'))
    # pick any window id from by_dir/by_name/by_email
    for k in ('by_dir','by_name','by_email'):
        vs = list(d.get(k, {}).values())
        if vs:
            print(vs[0]); break
except: pass
" 2>/dev/null)
    if [ -n "$sample_id" ]; then
      local alive
      alive=$(osascript -e "tell application \"Google Chrome\" to try
return (exists (window id \"$sample_id\"))
on error
return false
end try" 2>/dev/null)
      [ "$alive" != "true" ] && need_refresh=1
    else
      need_refresh=1
    fi
  fi
  if [ "$need_refresh" = "1" ]; then
    chrome_fingerprint > "$CHROME_CACHE"
  fi
  cat "$CHROME_CACHE"
}

# ---------------------------------------------------------------------------
# chrome_window_for <reference>
# reference can be:
#   - A profile directory name  ("Default", "Profile 1", "Profile 3")
#   - A substring of display name  ("Personal", "Work", "Uni")
#   - A full Google account email  ("you@gmail.com")
#   - A role alias defined in ~/.config/claude-mac-chrome/roles.json
# Prints the stable window ID, or empty string if no match.
# ---------------------------------------------------------------------------
chrome_window_for() {
  local ref="$1"
  local fp
  fp=$(chrome_fingerprint_cached)
  CHROME_REF="$ref" CHROME_ROLES="$CHROME_ROLES_FILE" python3 - "$fp" <<'PYEOF'
import json, os, sys
fp = json.loads(sys.argv[1])
ref = os.environ.get("CHROME_REF", "")
roles_path = os.environ.get("CHROME_ROLES", "")

by_dir = fp.get("by_dir", {})
by_name = fp.get("by_name", {})
by_email = fp.get("by_email", {})
catalog = fp.get("catalog", {})

def resolve(r):
    if not r:
        return ""
    # Exact matches first
    if r in by_dir:
        return by_dir[r]
    if r in by_name:
        return by_name[r]
    if r.lower() in by_email:
        return by_email[r.lower()]
    # Substring match against display names
    rl = r.lower()
    for name, wid in by_name.items():
        if rl in name.lower():
            return wid
    # Substring match against emails
    for email, wid in by_email.items():
        if rl in email.lower():
            return wid
    # Substring match against gaia names
    for dir_name, meta in catalog.items():
        if rl in (meta.get("gaia_name", "") or "").lower():
            return by_dir.get(dir_name, "")
    return ""

# First, try the direct reference
wid = resolve(ref)

# If no match, try role alias lookup
if not wid and roles_path and os.path.exists(roles_path):
    try:
        with open(roles_path) as f:
            roles = json.load(f)
        if ref in roles:
            wid = resolve(roles[ref])
    except Exception:
        pass

print(wid)
PYEOF
}

# ---------------------------------------------------------------------------
# chrome_tab_for_url <window_id> <url_substring>
# ---------------------------------------------------------------------------
chrome_tab_for_url() {
  local win="$1" pattern="$2"
  [ -z "$win" ] && return 1
  osascript <<APPLESCRIPT
tell application "Google Chrome"
  try
    repeat with t in tabs of window id "$win"
      if URL of t contains "$pattern" then return id of t
    end repeat
  end try
  return ""
end tell
APPLESCRIPT
}

# ---------------------------------------------------------------------------
# chrome_js <window_id> <tab_id> <js_snippet>
# Runs single-line JS. For multi-line, use Python wrapper (see docs/patterns.md).
# ---------------------------------------------------------------------------
chrome_js() {
  local win="$1" tab="$2" js="$3"
  osascript -e "tell application \"Google Chrome\" to execute (tab id \"$tab\" of window id \"$win\") javascript \"$js\""
}

# ---------------------------------------------------------------------------
# chrome_navigate <window_id> <tab_id> <url>
# ---------------------------------------------------------------------------
chrome_navigate() {
  local win="$1" tab="$2" url="$3"
  osascript -e "tell application \"Google Chrome\" to set URL of (tab id \"$tab\" of window id \"$win\") to \"$url\""
}

# ---------------------------------------------------------------------------
# chrome_new_tab <window_id> <url> → prints new tab's stable ID
# ---------------------------------------------------------------------------
chrome_new_tab() {
  local win="$1" url="$2"
  osascript <<APPLESCRIPT
tell application "Google Chrome"
  set newTab to make new tab at end of tabs of window id "$win" with properties {URL:"$url"}
  return id of newTab
end tell
APPLESCRIPT
}

# ---------------------------------------------------------------------------
# chrome_tab_url <window_id> <tab_id>
# ---------------------------------------------------------------------------
chrome_tab_url() {
  local win="$1" tab="$2"
  osascript -e "tell application \"Google Chrome\" to return URL of (tab id \"$tab\" of window id \"$win\")"
}

# ---------------------------------------------------------------------------
# Human-readable diagnostic
# ---------------------------------------------------------------------------
chrome_debug() {
  local fp
  fp=$(chrome_fingerprint_cached)
  echo "$fp" | python3 -c "
import sys, json
fp = json.load(sys.stdin)
catalog = fp.get('catalog', {})
by_dir = fp.get('by_dir', {})
unknown = fp.get('unknown', {})

print()
print('Profile catalog (from Chrome Local State):')
for dir_name, meta in catalog.items():
    email = meta.get('user_name','') or '(no Google account)'
    name = meta.get('name','') or dir_name
    print(f'  [{dir_name:12s}] {name:30s} {email}')

print()
print('Matched windows:')
if not by_dir:
    print('  (no windows matched — profiles may have no Google tabs open)')
for dir_name, wid in by_dir.items():
    meta = catalog.get(dir_name, {})
    name = meta.get('name','') or dir_name
    email = meta.get('user_name','')
    print(f'  win id={wid:12s}  {dir_name:12s}  {name:30s}  {email}')

if unknown:
    print()
    print('Unknown (email not in catalog — possibly Proton/Fastmail/other):')
    for email, wid in unknown.items():
        print(f'  win id={wid:12s}  {email}')
"
}

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cmd="$1"; shift
  case "$cmd" in
    catalog)       chrome_profiles_catalog ;;
    fingerprint)   chrome_fingerprint ;;
    cached)        chrome_fingerprint_cached ;;
    window_for)    chrome_window_for "$@" ;;
    tab_for_url)   chrome_tab_for_url "$@" ;;
    js)            chrome_js "$@" ;;
    navigate)      chrome_navigate "$@" ;;
    new_tab)       chrome_new_tab "$@" ;;
    tab_url)       chrome_tab_url "$@" ;;
    debug)         chrome_debug ;;
    refresh)       rm -f "$CHROME_CACHE"; chrome_fingerprint_cached ;;
    *)
      cat >&2 <<USAGE
chrome-lib.sh — professional Chrome automation for macOS multi-profile setups

CLI:
  chrome-lib.sh catalog                 # profiles from Chrome Local State
  chrome-lib.sh fingerprint             # {by_dir, by_name, by_email, unknown, catalog}
  chrome-lib.sh cached                  # cached fingerprint (auto-refresh on stale)
  chrome-lib.sh window_for <ref>        # ref = dir name | display name | email | role alias
  chrome-lib.sh tab_for_url <win> <substr>
  chrome-lib.sh js <win> <tab> <single-line-js>
  chrome-lib.sh navigate <win> <tab> <url>
  chrome-lib.sh new_tab <win> <url>     # returns new tab's stable ID
  chrome-lib.sh tab_url <win> <tab>
  chrome-lib.sh debug                   # human-readable diagnostic
  chrome-lib.sh refresh                 # force cache refresh

Environment:
  CHROME_USER_DATA_DIR                  # override Chrome user data dir
                                        # (default: ~/Library/Application Support/Google/Chrome)
  CHROME_ROLES_FILE                     # override roles alias file
                                        # (default: ~/.config/claude-mac-chrome/roles.json)

Source it from scripts to use the functions directly:
  source ~/Documents/dp-workspace/claude-mac-chrome/skills/chrome-multi-profile/chrome-lib.sh
USAGE
      exit 2
      ;;
  esac
fi
