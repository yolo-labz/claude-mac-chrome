#!/usr/bin/env bash
# chrome-lib.sh — Chrome automation using authoritative profile catalog + stable IDs
#
# Requires: Bash 4.0+ (for associative arrays), Python 3, macOS with Chrome.
# Safe to source; sets strict mode only in CLI entry point.
# shellcheck shell=bash disable=SC2016  # intentional single-quoted python/applescript
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

readonly CHROME_USER_DATA="${CHROME_USER_DATA_DIR:-$HOME/Library/Application Support/Google/Chrome}"
readonly CHROME_LOCAL_STATE="$CHROME_USER_DATA/Local State"
readonly CHROME_CACHE="${TMPDIR:-/tmp}/chrome-fingerprint.json"
readonly CHROME_ROLES_FILE="${CHROME_ROLES_FILE:-$HOME/.config/claude-mac-chrome/roles.json}"

# Emit errors to stderr with a consistent prefix.
_chrome_err() {
  printf '[chrome-lib] error: %s\n' "$*" >&2
}

_chrome_warn() {
  printf '[chrome-lib] warn: %s\n' "$*" >&2
}

# ---------------------------------------------------------------------------
# Tier 1 — Authoritative profile catalog from Chrome's own Local State file
# ---------------------------------------------------------------------------
# Returns JSON: {"Default":{"dir":"Default","name":"Personal","user_name":"you@example.com",...},...}
chrome_profiles_catalog() {
  LOCAL_STATE="$CHROME_LOCAL_STATE" python3 << 'PYEOF'
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
  osascript << 'APPLESCRIPT'
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
# Core fingerprint — multi-signal deterministic profile detection
# ---------------------------------------------------------------------------
# Pipeline:
#   Step A. Read Local State catalog → list of profiles on the machine
#   Step B. Enumerate open Chrome windows + their tabs (via AppleScript)
#   Step C. For each window:
#             - Extract emails from tab titles
#             - Build candidate list of profiles whose email matches
#   Step D. For each window, resolve the candidate list:
#             - 0 candidates → unknown; try URL overlap against all profiles
#             - 1 candidate → single-email match, assign directly
#             - 2+ candidates (same-email profile collision) → disambiguate via
#               URL overlap between the window's live tab URLs and each
#               candidate profile's Sessions/Tabs_<latest> SNSS file
#   Step E. On ties or empty overlap, fall back to SNSS file mtime (most
#           recently modified profile wins for the currently-active window)
#
# Output JSON shape:
#   {
#     "by_dir":     {"Default": "W1", "Profile 1": "W2", "Profile 3": "W3"},
#     "by_name":    {"Personal": "W1", "Study": "W2", "Work": "W3"},
#     "by_email":   {"you@gmail.com": "W1", ...},
#     "unknown":    {"random@x.com": "W4"},
#     "assignments": {
#       "W1": {"profile_dir":"Default","method":"email_unique","score":null,
#              "email":"you@gmail.com","name":"Personal"},
#       "W2": {"profile_dir":"Profile 1","method":"url_overlap","score":0.87,
#              "email":"you@gmail.com","name":"Personal Shopping"},
#       ...
#     },
#     "catalog": {...}
#   }
chrome_fingerprint() {
  local catalog_json windows_raw
  catalog_json=$(chrome_profiles_catalog)
  windows_raw=$(chrome_windows_raw)
  CATALOG="$catalog_json" RAW="$windows_raw" USER_DATA="$CHROME_USER_DATA" python3 << 'PYEOF'
import json, os, re, sys
from collections import defaultdict

catalog = json.loads(os.environ.get("CATALOG", "{}"))
raw = os.environ.get("RAW", "")
user_data = os.environ.get("USER_DATA", "")

EMAIL_RE = re.compile(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+')
IGNORED_PREFIXES = ("noreply", "no-reply", "support", "info", "hello", "mailer", "notifications")

# ---------------------------------------------------------------------------
# Step A: email → [profile_dir, ...] (list, not dict, to support collisions)
# ---------------------------------------------------------------------------
email_to_dirs = defaultdict(list)
for dir_name, meta in catalog.items():
    em = meta.get("user_name") or ""
    if em:
        email_to_dirs[em].append(dir_name)

# ---------------------------------------------------------------------------
# Step B: parse raw windows dump → {wid: {"tabs": [{title,url,tid}], "emails": set}}
# ---------------------------------------------------------------------------
windows = defaultdict(lambda: {"tabs": [], "emails": set(), "urls": set()})
for line in raw.split("\n"):
    if not line.strip():
        continue
    parts = line.split("\t", 3)
    if len(parts) < 4:
        continue
    wid, tid, title, url = parts
    w = windows[wid]
    w["tabs"].append({"tid": tid, "title": title, "url": url})
    if url:
        w["urls"].add(url)
    # Extract emails from title
    for m in EMAIL_RE.finditer(title):
        em = m.group(0).lower()
        if not any(em.startswith(p) for p in IGNORED_PREFIXES):
            w["emails"].add(em)

# ---------------------------------------------------------------------------
# SNSS URL extraction — parse profile's latest Tabs_* file for open URLs
# ---------------------------------------------------------------------------
def extract_urls_from_file(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except Exception:
        return set()
    urls = set()
    # Find sequences of printable ASCII (like `strings`)
    for chunk in re.findall(rb'[\x20-\x7e]{8,}', data):
        try:
            s = chunk.decode("ascii", errors="ignore")
        except Exception:
            continue
        for m in re.finditer(r'https?://[^\s<>"\'\\`^{}|]+', s):
            url = m.group(0).rstrip(',.);]')
            if len(url) < 512:
                urls.add(url)
    return urls

def profile_snss_urls(profile_dir):
    sessions = os.path.join(user_data, profile_dir, "Sessions")
    if not os.path.isdir(sessions):
        return set(), 0
    tabs_files = [f for f in os.listdir(sessions) if f.startswith("Tabs_")]
    if not tabs_files:
        return set(), 0
    # Pick the most recently modified Tabs_ file
    tabs_files_full = [os.path.join(sessions, f) for f in tabs_files]
    latest = max(tabs_files_full, key=lambda p: os.path.getmtime(p))
    mtime = os.path.getmtime(latest)
    return extract_urls_from_file(latest), mtime

# Cache SNSS URL sets (compute once per profile)
snss_cache = {}
def get_snss(profile_dir):
    if profile_dir not in snss_cache:
        snss_cache[profile_dir] = profile_snss_urls(profile_dir)
    return snss_cache[profile_dir]

# ---------------------------------------------------------------------------
# Similarity metric
# ---------------------------------------------------------------------------
def url_overlap_score(window_urls, profile_urls):
    """
    Fraction of the window's URLs that also appear in the profile's SNSS set.
    Range 0..1. Higher = stronger evidence this window belongs to this profile.
    Uses A-coverage (how much of A is covered by B) because the profile's SNSS
    URL set is typically larger than the window's live URLs (includes history).
    """
    if not window_urls:
        return 0.0
    overlap = window_urls & profile_urls
    return len(overlap) / len(window_urls)

# ---------------------------------------------------------------------------
# Step C+D+E: assign each window to a profile
# ---------------------------------------------------------------------------
assignments = {}  # wid -> {profile_dir, method, score, ...}
by_dir = {}
by_name = {}
by_email = {}
unknown = {}

for wid, w in windows.items():
    emails = w["emails"]
    urls = w["urls"]

    # Build candidate set
    candidates = set()
    matched_email = None
    for em in emails:
        if em in email_to_dirs:
            candidates.update(email_to_dirs[em])
            if not matched_email:
                matched_email = em

    if len(candidates) == 1:
        # Single unambiguous email match
        profile_dir = next(iter(candidates))
        meta = catalog.get(profile_dir, {})
        assignments[wid] = {
            "profile_dir": profile_dir,
            "name": meta.get("name", profile_dir),
            "email": meta.get("user_name", ""),
            "method": "email_unique",
            "score": None,
        }
        continue

    if not candidates:
        # No email match — the window might have no Google tab, or the email
        # doesn't exist in Local State catalog. Try URL overlap against ALL
        # profiles in the catalog as a last-resort disambiguation.
        candidates = set(catalog.keys())
        method = "url_fallback"
        # Also record any raw email for the unknown bucket
        for em in emails:
            unknown[em] = wid
    else:
        # 2+ candidates → same-email collision, disambiguate via URL overlap
        method = "url_overlap"

    # Score each candidate by URL overlap with its SNSS file
    scored = []
    for pd in candidates:
        snss_urls, mtime = get_snss(pd)
        score = url_overlap_score(urls, snss_urls)
        scored.append((pd, score, mtime))

    # Sort by score descending, then by mtime descending (most recent wins ties)
    scored.sort(key=lambda t: (t[1], t[2]), reverse=True)
    best_pd, best_score, best_mtime = scored[0]

    if best_score == 0 and method == "url_fallback":
        # No signal at all — can't assign this window to any profile
        assignments[wid] = {
            "profile_dir": None,
            "name": None,
            "email": (next(iter(emails)) if emails else ""),
            "method": "no_signal",
            "score": 0.0,
        }
        continue

    meta = catalog.get(best_pd, {})
    assignments[wid] = {
        "profile_dir": best_pd,
        "name": meta.get("name", best_pd),
        "email": meta.get("user_name", ""),
        "method": method,
        "score": round(best_score, 3),
    }

# ---------------------------------------------------------------------------
# Build multi-index maps from the assignments
# ---------------------------------------------------------------------------
for wid, a in assignments.items():
    pd = a.get("profile_dir")
    if not pd:
        continue
    meta = catalog.get(pd, {})
    by_dir[pd] = wid
    name = meta.get("name", "")
    if name:
        by_name[name] = wid
    em = meta.get("user_name", "")
    if em:
        by_email[em] = wid

result = {
    "by_dir": by_dir,
    "by_name": by_name,
    "by_email": by_email,
    "unknown": unknown,
    "assignments": assignments,
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

  if [[ ! -s "$CHROME_CACHE" ]]; then
    need_refresh=1
  else
    local sample_id
    sample_id=$(CHROME_CACHE_PATH="$CHROME_CACHE" python3 -c '
import json, os, sys
try:
    with open(os.environ["CHROME_CACHE_PATH"]) as f:
        d = json.load(f)
    for k in ("by_dir", "by_name", "by_email"):
        vs = list(d.get(k, {}).values())
        if vs:
            print(vs[0])
            break
except Exception:
    pass
' 2> /dev/null)

    if [[ -n "$sample_id" ]]; then
      local alive
      alive=$(osascript -e "tell application \"Google Chrome\" to try
return (exists (window id \"$sample_id\"))
on error
return false
end try" 2> /dev/null)
      [[ "$alive" != "true" ]] && need_refresh=1
    else
      need_refresh=1
    fi
  fi

  if [[ "$need_refresh" == "1" ]]; then
    local tmp
    tmp=$(mktemp -t chrome-fingerprint.XXXXXX)
    if chrome_fingerprint > "$tmp"; then
      mv -f "$tmp" "$CHROME_CACHE"
    else
      rm -f "$tmp"
      _chrome_err "failed to refresh fingerprint cache"
      return 1
    fi
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
  CHROME_REF="$ref" CHROME_ROLES="$CHROME_ROLES_FILE" python3 - "$fp" << 'PYEOF'
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
  [[ -z "$win" ]] && {
    _chrome_err "chrome_tab_for_url: window id required"
    return 1
  }
  [[ -z "$pattern" ]] && {
    _chrome_err "chrome_tab_for_url: url substring required"
    return 1
  }
  osascript << APPLESCRIPT
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
  osascript << APPLESCRIPT
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
# Human-readable diagnostic with match method + confidence
# ---------------------------------------------------------------------------
chrome_debug() {
  local fp
  fp=$(chrome_fingerprint_cached)
  echo "$fp" | python3 -c "
import sys, json
fp = json.load(sys.stdin)
catalog = fp.get('catalog', {})
assignments = fp.get('assignments', {})
unknown = fp.get('unknown', {})

method_label = {
    'email_unique':  'email (unique)',
    'url_overlap':   'URL overlap (same-email disambiguation)',
    'url_fallback':  'URL overlap (no email signal)',
    'no_signal':     '(unassigned)',
}

print()
print('Profile catalog (from Chrome Local State):')
for dir_name, meta in catalog.items():
    email = meta.get('user_name','') or '(no Google account)'
    name = meta.get('name','') or dir_name
    ephemeral = ' [ephemeral]' if meta.get('is_ephemeral') else ''
    print(f'  [{dir_name:12s}] {name:30s} {email}{ephemeral}')

print()
print('Matched windows:')
if not assignments:
    print('  (no windows matched — Chrome may not be running, or all windows have no signal)')
for wid, a in assignments.items():
    pd = a.get('profile_dir') or '?'
    name = a.get('name') or pd
    email = a.get('email','')
    method = method_label.get(a.get('method'), a.get('method','?'))
    score = a.get('score')
    score_str = f'  conf={score:.2f}' if score is not None else ''
    print(f'  win id={wid:12s}  {pd:12s}  {name:30s}  {email:30s}  [{method}]{score_str}')

if unknown:
    print()
    print('Unknown emails (not in catalog — Proton/Fastmail/external):')
    for email, wid in unknown.items():
        print(f'  win id={wid:12s}  {email}')
"
}

# ---------------------------------------------------------------------------
# chrome_profile_urls <profile_dir>
# Dump the URL set that the library sees for a given profile by parsing the
# profile's latest Sessions/Tabs_* SNSS file. Useful for debugging same-email
# disambiguation ('why did window X get assigned to profile Y?').
# ---------------------------------------------------------------------------
chrome_profile_urls() {
  local profile_dir="$1"
  [[ -z "$profile_dir" ]] && {
    _chrome_err "usage: chrome_profile_urls <profile_dir>"
    return 1
  }
  USER_DATA="$CHROME_USER_DATA" PROFILE_DIR="$profile_dir" python3 << 'PYEOF'
import os, re, sys
user_data = os.environ["USER_DATA"]
profile = os.environ["PROFILE_DIR"]
sessions = os.path.join(user_data, profile, "Sessions")
if not os.path.isdir(sessions):
    sys.stderr.write(f"error: {sessions} does not exist\n")
    sys.exit(1)
tabs_files = [f for f in os.listdir(sessions) if f.startswith("Tabs_")]
if not tabs_files:
    sys.stderr.write(f"error: no Tabs_* files in {sessions}\n")
    sys.exit(1)
tabs_files_full = [os.path.join(sessions, f) for f in tabs_files]
latest = max(tabs_files_full, key=lambda p: os.path.getmtime(p))
sys.stderr.write(f"# reading {os.path.basename(latest)} (mtime {int(os.path.getmtime(latest))})\n")
with open(latest, "rb") as f:
    data = f.read()
urls = set()
for chunk in re.findall(rb'[\x20-\x7e]{8,}', data):
    s = chunk.decode("ascii", errors="ignore")
    for m in re.finditer(r'https?://[^\s<>"\'\\`^{}|]+', s):
        url = m.group(0).rstrip(',.);]')
        if len(url) < 512:
            urls.add(url)
for u in sorted(urls):
    print(u)
PYEOF
}

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Strict mode only in CLI — sourcing shouldn't impose it on the caller.
  set -euo pipefail
  IFS=$'\n\t'

  if [[ $# -lt 1 ]]; then
    cmd=""
  else
    cmd="$1"
    shift
  fi

  case "$cmd" in
    catalog) chrome_profiles_catalog ;;
    fingerprint) chrome_fingerprint ;;
    cached) chrome_fingerprint_cached ;;
    window_for) chrome_window_for "$@" ;;
    tab_for_url) chrome_tab_for_url "$@" ;;
    js) chrome_js "$@" ;;
    navigate) chrome_navigate "$@" ;;
    new_tab) chrome_new_tab "$@" ;;
    tab_url) chrome_tab_url "$@" ;;
    debug) chrome_debug ;;
    profile_urls) chrome_profile_urls "$@" ;;
    refresh)
      rm -f "$CHROME_CACHE"
      chrome_fingerprint_cached
      ;;
    *)
      cat >&2 << USAGE
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
  chrome-lib.sh debug                   # human-readable diagnostic with match method + confidence
  chrome-lib.sh profile_urls <profile>  # dump SNSS-extracted URL set for a profile (debugging)
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
