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
  if [[ ! -f "$CHROME_LOCAL_STATE" ]]; then
    _chrome_err "Chrome Local State not found at $CHROME_LOCAL_STATE"
    printf '{}'
    return 0
  fi
  if ! command -v jq > /dev/null 2>&1; then
    _chrome_err "jq is required but not found. Install via: brew install jq"
    printf '{}'
    return 1
  fi
  jq -r '
    (.profile.info_cache // {}) | to_entries | map({
      key: .key,
      value: {
        dir: .key,
        name: (if (.value.name // "") == "" then .key else .value.name end),
        user_name: ((.value.user_name // "") | ascii_downcase),
        gaia_name: (.value.gaia_name // ""),
        is_ephemeral: (if .value.is_ephemeral then true else false end)
      }
    }) | from_entries
  ' "$CHROME_LOCAL_STATE" 2> /dev/null || {
    _chrome_err "failed to parse Local State"
    printf '{}'
  }
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
# Tier 2b — Window given names (Chrome M118+ feature 001)
# ---------------------------------------------------------------------------
# Output format (tab-delimited, one row per window):
#   window_id \t given_name
# Given names prefixed with "cmc:" are authoritative identity labels set by
# this library. Format: "cmc:<profile_dir>" (e.g., "cmc:Default").
# Persists across Chrome restarts when "Continue where you left off" is on.
_chrome_window_given_names() {
  osascript << 'APPLESCRIPT'
tell application "Google Chrome"
  set out to ""
  repeat with w in windows
    set wid to id of w
    try
      set gn to given name of w
    on error
      set gn to ""
    end try
    set out to out & wid & "	" & gn & linefeed
  end repeat
  return out
end tell
APPLESCRIPT
}

# Register a window with a given name label for persistent identity.
# Usage: chrome_register_window <window_id> <profile_dir>
# The given name is visible in the window title bar and persists across
# restarts. Uses "cmc:" prefix to distinguish from user-set names.
chrome_register_window() {
  local wid="$1" profile_dir="$2"
  [[ -z "$wid" || -z "$profile_dir" ]] && {
    _chrome_err "usage: chrome_register_window <window_id> <profile_dir>"
    return 1
  }
  local label="cmc:${profile_dir}"
  osascript -e "tell application \"Google Chrome\" to set given name of window id $wid to \"$label\"" 2> /dev/null || {
    _chrome_err "failed to set given name on window $wid (requires Chrome M118+)"
    return 1
  }
}

# Unregister a window's identity label (clears given name).
chrome_unregister_window() {
  local wid="$1"
  [[ -z "$wid" ]] && return 1
  osascript -e "tell application \"Google Chrome\" to set given name of window id $wid to \"\"" 2> /dev/null
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
  local catalog_json windows_raw given_names_raw
  catalog_json=$(chrome_profiles_catalog)
  windows_raw=$(chrome_windows_raw)
  given_names_raw=$(_chrome_window_given_names)

  if ! command -v jq > /dev/null 2>&1; then
    _chrome_err "jq is required but not found. Install via: brew install jq"
    return 1
  fi

  # Step A: build email → [profile_dirs] mapping from catalog
  local email_to_dirs
  email_to_dirs=$(printf '%s' "$catalog_json" | jq -r '
    [to_entries[] | select(.value.user_name != "") |
     {email: .value.user_name, dir: .key}] |
    group_by(.email) |
    map({key: .[0].email, value: [.[].dir]}) |
    from_entries
  ')

  # Step A2 (feature 001): parse given names — cmc:<profile_dir> is authoritative
  local -A given_name_map  # window_id → profile_dir (only for cmc: entries)
  local gn_line gn_wid gn_val
  while IFS=$'\t' read -r gn_wid gn_val; do
    [[ -z "$gn_wid" ]] && continue
    if [[ "$gn_val" == cmc:* ]]; then
      given_name_map["$gn_wid"]="${gn_val#cmc:}"
    fi
  done <<< "$given_names_raw"

  # Step B: parse raw windows dump, extract emails from tab titles
  local assignments_json="{}"
  local by_dir="{}" by_name="{}" by_email="{}" unknown="{}"
  local wid matched_dir matched_email method

  # Collect unique window IDs
  local window_ids
  window_ids=$(printf '%s' "$windows_raw" | cut -f1 | sort -u)

  if [[ -z "$window_ids" ]]; then
    jq -n --argjson catalog "$catalog_json" '{
      by_dir: {}, by_name: {}, by_email: {},
      unknown: {}, assignments: {}, catalog: $catalog
    }'
    return 0
  fi

  local -a wid_array
  mapfile -t wid_array <<< "$window_ids"

  local wid
  for wid in "${wid_array[@]}"; do
    [[ -z "$wid" ]] && continue

    # Feature 001: if window has a cmc: given name, that's authoritative
    if [[ -n "${given_name_map[$wid]:-}" ]]; then
      matched_dir="${given_name_map[$wid]}"
      method="given_name"
      local meta_name meta_email
      meta_name=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].name // $d')
      meta_email=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].user_name // ""')
      assignments_json=$(printf '%s' "$assignments_json" | jq --arg w "$wid" --arg pd "$matched_dir" \
        --arg name "$meta_name" --arg email "$meta_email" --arg method "$method" \
        '. + {($w): {profile_dir: $pd, name: $name, email: $email, method: $method, score: null}}')
      by_dir=$(printf '%s' "$by_dir" | jq --arg pd "$matched_dir" --arg w "$wid" '. + {($pd): $w}')
      by_name=$(printf '%s' "$by_name" | jq --arg name "$meta_name" --arg w "$wid" '. + {($name): $w}')
      by_email=$(printf '%s' "$by_email" | jq --arg email "$meta_email" --arg w "$wid" 'if $email != "" then . + {($email): $w} else . end')
      continue
    fi

    # Extract tab titles for this window, find emails via grep
    local tab_titles
    tab_titles=$(printf '%s' "$windows_raw" | awk -F'\t' -v w="$wid" '$1==w {print $3}')

    # Extract emails from titles (grep for email-like patterns)
    local raw_emails
    raw_emails=$(printf '%s' "$tab_titles" |
      grep -oiE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' |
      tr '[:upper:]' '[:lower:]' |
      grep -vE '^(noreply|no-reply|support|info|hello|mailer|notifications)' |
      sort -u || true)

    # Find matching profile dirs for extracted emails
    local candidates="" matched_email=""
    local -a email_array
    mapfile -t email_array <<< "$raw_emails"
    local em
    for em in "${email_array[@]}"; do
      [[ -z "$em" ]] && continue
      local dirs_for_email
      dirs_for_email=$(printf '%s' "$email_to_dirs" | jq -r --arg e "$em" '.[$e] // [] | .[]' 2> /dev/null)
      if [[ -n "$dirs_for_email" ]]; then
        candidates=$(printf '%s\n%s' "$candidates" "$dirs_for_email" | sort -u | sed '/^$/d')
        [[ -z "$matched_email" ]] && matched_email="$em"
      fi
    done

    local candidate_count
    candidate_count=$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')

    if [[ "$candidate_count" -eq 1 ]]; then
      matched_dir=$(printf '%s' "$candidates" | sed '/^$/d' | head -1)
      method="email_unique"
      local meta_name meta_email
      meta_name=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].name // $d')
      meta_email=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].user_name // ""')
      assignments_json=$(printf '%s' "$assignments_json" | jq --arg w "$wid" --arg pd "$matched_dir" \
        --arg name "$meta_name" --arg email "$meta_email" --arg method "$method" \
        '. + {($w): {profile_dir: $pd, name: $name, email: $email, method: $method, score: null}}')
      by_dir=$(printf '%s' "$by_dir" | jq --arg pd "$matched_dir" --arg w "$wid" '. + {($pd): $w}')
      by_name=$(printf '%s' "$by_name" | jq --arg name "$meta_name" --arg w "$wid" '. + {($name): $w}')
      by_email=$(printf '%s' "$by_email" | jq --arg email "$meta_email" --arg w "$wid" 'if $email != "" then . + {($email): $w} else . end')
      # Feature 001: auto-register on successful email match (write-on-resolve)
      chrome_register_window "$wid" "$matched_dir" 2> /dev/null || true
    elif [[ "$candidate_count" -eq 0 ]]; then
      # No email match — record as no_signal
      local first_email
      first_email=$(printf '%s' "$raw_emails" | head -1)
      assignments_json=$(printf '%s' "$assignments_json" | jq --arg w "$wid" --arg email "${first_email:-}" \
        '. + {($w): {profile_dir: null, name: null, email: $email, method: "no_signal", score: 0.0}}')
      if [[ -n "$first_email" ]]; then
        unknown=$(printf '%s' "$unknown" | jq --arg email "$first_email" --arg w "$wid" '. + {($email): $w}')
      fi
    else
      # Multiple candidates — same-email collision, assign first match for now
      matched_dir=$(printf '%s' "$candidates" | sed '/^$/d' | head -1)
      method="email_tab"
      local meta_name meta_email
      meta_name=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].name // $d')
      meta_email=$(printf '%s' "$catalog_json" | jq -r --arg d "$matched_dir" '.[$d].user_name // ""')
      assignments_json=$(printf '%s' "$assignments_json" | jq --arg w "$wid" --arg pd "$matched_dir" \
        --arg name "$meta_name" --arg email "$meta_email" --arg method "$method" \
        '. + {($w): {profile_dir: $pd, name: $name, email: $email, method: $method, score: null}}')
      by_dir=$(printf '%s' "$by_dir" | jq --arg pd "$matched_dir" --arg w "$wid" '. + {($pd): $w}')
      by_name=$(printf '%s' "$by_name" | jq --arg name "$meta_name" --arg w "$wid" '. + {($name): $w}')
      by_email=$(printf '%s' "$by_email" | jq --arg email "$meta_email" --arg w "$wid" 'if $email != "" then . + {($email): $w} else . end')
      # Feature 001: auto-register on resolution
      chrome_register_window "$wid" "$matched_dir" 2> /dev/null || true
    fi
  done

  jq -n \
    --argjson by_dir "$by_dir" \
    --argjson by_name "$by_name" \
    --argjson by_email "$by_email" \
    --argjson unknown "$unknown" \
    --argjson assignments "$assignments_json" \
    --argjson catalog "$catalog_json" \
    '{by_dir: $by_dir, by_name: $by_name, by_email: $by_email,
      unknown: $unknown, assignments: $assignments, catalog: $catalog}'
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
    sample_id=$(jq -r '
      (.by_dir // {} | to_entries | .[0].value // empty),
      (.by_name // {} | to_entries | .[0].value // empty),
      (.by_email // {} | to_entries | .[0].value // empty)
    ' "$CHROME_CACHE" 2> /dev/null | head -1)

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

  _chrome_resolve_ref() {
    local r="$1" rl
    rl=$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')
    [[ -z "$rl" ]] && return

    # Exact matches: by_dir, by_name, by_email
    local result
    result=$(printf '%s' "$fp" | jq -r --arg r "$r" --arg rl "$rl" '
      (if .by_dir[$r] then .by_dir[$r]
       elif .by_name[$r] then .by_name[$r]
       elif .by_email[$rl] then .by_email[$rl]
       else null end) // empty
    ' 2> /dev/null)
    if [[ -n "$result" ]]; then
      printf '%s' "$result"
      return
    fi

    # Substring match against display names, emails, gaia names
    result=$(printf '%s' "$fp" | jq -r --arg rl "$rl" '
      (.by_name | to_entries[] | select(.key | ascii_downcase | contains($rl)) | .value) // empty
    ' 2> /dev/null | head -1)
    if [[ -n "$result" ]]; then
      printf '%s' "$result"
      return
    fi

    result=$(printf '%s' "$fp" | jq -r --arg rl "$rl" '
      (.by_email | to_entries[] | select(.key | ascii_downcase | contains($rl)) | .value) // empty
    ' 2> /dev/null | head -1)
    if [[ -n "$result" ]]; then
      printf '%s' "$result"
      return
    fi

    result=$(printf '%s' "$fp" | jq -r --arg rl "$rl" '
      .catalog | to_entries[] |
      select((.value.gaia_name // "") | ascii_downcase | contains($rl)) |
      .key as $dir | .value | ($dir)
    ' 2> /dev/null | head -1)
    if [[ -n "$result" ]]; then
      local wid_for_dir
      wid_for_dir=$(printf '%s' "$fp" | jq -r --arg d "$result" '.by_dir[$d] // empty')
      [[ -n "$wid_for_dir" ]] && printf '%s' "$wid_for_dir"
      return
    fi

    # Fallback: search the "unknown" bucket (windows matched by tab-title
    # email that doesn't correspond to any catalog profile — e.g. Proton
    # email in a window whose profile is registered under Gmail).
    result=$(printf '%s' "$fp" | jq -r --arg rl "$rl" '
      (.unknown // {}) | to_entries[] |
      select(.key | ascii_downcase | contains($rl)) | .value
    ' 2> /dev/null | head -1)
    if [[ -n "$result" ]]; then
      printf '%s' "$result"
    fi
  }

  # Try direct reference
  local wid
  wid=$(_chrome_resolve_ref "$ref")

  # If no match, try role alias lookup
  if [[ -z "$wid" && -f "$CHROME_ROLES_FILE" ]]; then
    local alias_target
    alias_target=$(jq -r --arg r "$ref" '.[$r] // empty' "$CHROME_ROLES_FILE" 2> /dev/null)
    if [[ -n "$alias_target" ]]; then
      wid=$(_chrome_resolve_ref "$alias_target")
    fi
  fi

  printf '%s\n' "$wid"
  unset -f _chrome_resolve_ref
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
  # Escape JS for AppleScript. AppleScript string literals use JSON-compatible
  # backslash escapes (\", \\, \n, \t). jq -Rs . produces exactly that format.
  local js_quoted
  js_quoted=$(printf '%s' "$js" | jq -Rs . 2> /dev/null)
  [[ -z "$js_quoted" ]] && {
    _chrome_err "chrome_js: failed to JSON-escape JS (jq required)"
    return 1
  }
  osascript -e "tell application \"Google Chrome\" to execute (tab id \"$tab\" of window id \"$win\") javascript $js_quoted"
}

# ---------------------------------------------------------------------------
# chrome_navigate <window_id> <tab_id> <url>
# ---------------------------------------------------------------------------
chrome_navigate() {
  local win="$1" tab="$2" url="$3"
  local url_quoted
  url_quoted=$(printf '%s' "$url" | jq -Rs . 2> /dev/null) || {
    _chrome_err "chrome_navigate: failed to escape URL (jq required)"
    return 1
  }
  osascript -e "tell application \"Google Chrome\" to set URL of (tab id \"$tab\" of window id \"$win\") to $url_quoted"
}

# ---------------------------------------------------------------------------
# chrome_new_tab <window_id> <url> → prints new tab's stable ID
# ---------------------------------------------------------------------------
chrome_new_tab() {
  local win="$1" url="$2"
  local url_quoted
  url_quoted=$(printf '%s' "$url" | jq -Rs . 2> /dev/null) || {
    _chrome_err "chrome_new_tab: failed to escape URL (jq required)"
    return 1
  }
  osascript -e "tell application \"Google Chrome\" to return id of (make new tab at end of tabs of window id \"$win\" with properties {URL:$url_quoted})"
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

  printf '\n'
  printf 'Profile catalog (from Chrome Local State):\n'
  printf '%s' "$fp" | jq -r '
    .catalog | to_entries[] |
    "  [\(.key | . + " " * (12 - length))] \(
      (if .value.name == "" then .key else .value.name end) + " " * 30
      | .[:30])  \(
      if .value.user_name == "" then "(no Google account)" else .value.user_name end)\(
      if .value.is_ephemeral then " [ephemeral]" else "" end)"
  '

  printf '\n'
  printf 'Matched windows:\n'
  local assignment_count
  assignment_count=$(printf '%s' "$fp" | jq '.assignments | length')
  if [[ "$assignment_count" -eq 0 ]]; then
    printf '  (no windows matched — Chrome may not be running, or all windows have no signal)\n'
  else
    printf '%s' "$fp" | jq -r '
      def method_label:
        {"email_unique": "email (unique)",
         "email_tab": "email (tab title)",
         "ax_avatar": "AX avatar button",
         "url_overlap": "URL overlap",
         "url_fallback": "URL overlap (no email)",
         "no_signal": "(unassigned)"};
      .assignments | to_entries[] |
      "  win id=\(.key)  \(.value.profile_dir // "?")  \(
        (.value.name // .value.profile_dir // "?") + " " * 30 | .[:30])  \(
        (.value.email // "") + " " * 30 | .[:30])  [\(
        method_label[.value.method] // .value.method // "?")]\(
        if .value.score != null then "  conf=\(.value.score)" else "" end)"
    '
  fi

  local unknown_count
  unknown_count=$(printf '%s' "$fp" | jq '.unknown | length')
  if [[ "$unknown_count" -gt 0 ]]; then
    printf '\n'
    printf 'Unknown emails (not in catalog):\n'
    printf '%s' "$fp" | jq -r '.unknown | to_entries[] | "  win id=\(.value)  \(.key)"'
  fi
}

# chrome_profile_urls — REMOVED in v0.4.0 (was SNSS debugging tool, replaced by AX + live URL overlap)

# ---------------------------------------------------------------------------
# v0.7.0 — Workflow orchestration helpers (feature 004)
# ---------------------------------------------------------------------------

# Mail provider URL patterns (readonly, NOT overridable — NFR-JS-4)
# Each index in PROVIDERS matches the corresponding index in UNREAD_RE.
# Adding a provider requires code change + PR review.
readonly -a CHROME_MAIL_PROVIDERS=(
  "mail.google.com"
  "mail.proton.me"
  "app.fastmail.com"
  "outlook.live.com"
  "outlook.office.com"
)
readonly -a CHROME_MAIL_UNREAD_RE=(
  '\(([0-9]+)\)'
  '^\(([0-9]+)\)'
  '\(([0-9]+)\)'
  '\(([0-9]+)\)'
  '\(([0-9]+)\)'
)

# Workflow state path + directory (XDG-convention, 0700 perms).
_chrome_workflow_state_dir() {
  printf '%s' "${HOME}/.local/state/claude-mac-chrome"
}

_chrome_workflow_state_path() {
  printf '%s' "$(_chrome_workflow_state_dir)/workflow-state.json"
}

_chrome_workflow_state_ensure_dir() {
  local dir
  dir=$(_chrome_workflow_state_dir)
  if [[ -L "$dir" ]]; then
    _chrome_warn "Workflow state dir is a symlink — refusing"
    return 1
  fi
  (umask 077 && mkdir -p "$dir") || {
    _chrome_err "Cannot create workflow state dir $dir"
    return 1
  }
}

# Snapshot directory (XDG config, 0700 perms).
_chrome_snapshot_dir() {
  printf '%s' "${HOME}/.config/claude-mac-chrome/snapshots"
}

_chrome_snapshot_ensure_dir() {
  local dir
  dir=$(_chrome_snapshot_dir)
  if [[ -L "$dir" ]]; then
    _chrome_warn "Snapshot dir is a symlink — refusing"
    return 1
  fi
  (umask 077 && mkdir -p "$dir") || {
    _chrome_err "Cannot create snapshot dir $dir"
    return 1
  }
}

# Validate snapshot name — reject (not sanitize) names with path traversal
# or filesystem edge cases. Per NFR-SNAP-3.
_chrome_validate_snapshot_name() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
    _chrome_err "invalid snapshot name: must match ^[a-zA-Z0-9_-]{1,64}\$"
    return 1
  fi
}

# Strip URL query strings and fragments before persisting. Per NFR-SNAP-1.
_chrome_strip_url_query() {
  local url="$1"
  printf '%s' "${url%%[?#]*}"
}

# JS injection rate guard — tracks calls per invocation via a counter var.
# Per NFR-JS-5. Caller sets _CHROME_JS_CALL_COUNT=0 before loop, guard
# increments and warns when cap exceeded.
_chrome_js_rate_guard() {
  : "${_CHROME_JS_CALL_COUNT:=0}"
  local cap="${CHROME_LIB_MAX_JS_CALLS:-50}"
  _CHROME_JS_CALL_COUNT=$((_CHROME_JS_CALL_COUNT + 1))
  if ((_CHROME_JS_CALL_COUNT > cap)); then
    _chrome_warn "JS call cap exceeded ($cap); skipping remaining tabs"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# v0.7.0 — chrome_check_inboxes: cross-profile unread count (feature 004 US1)
# ---------------------------------------------------------------------------
# Emits one structured line per profile:
#   PROFILE=<name> EMAIL=<email> UNREAD=<N> DELTA=<+/-N> STATUS=<status>
# Status: ok | window_not_found | tab_not_found | js_error
# Always exits 0 — partial results are expected. Per NFR-ERR-1.
chrome_check_inboxes() {
  local fp
  fp=$(chrome_fingerprint_cached)

  # Read prior state for delta computation
  local state_path prior_state
  state_path=$(_chrome_workflow_state_path)
  if [[ -f "$state_path" ]]; then
    prior_state=$(cat "$state_path" 2> /dev/null || printf '{}')
  else
    prior_state='{}'
  fi

  # Reset JS call counter for rate guard
  _CHROME_JS_CALL_COUNT=0

  # Build new state as we go
  local new_counts="{}"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Iterate catalog profiles (not just matched windows — report all)
  local -a profile_dirs
  mapfile -t profile_dirs < <(printf '%s' "$fp" | jq -r '.catalog | keys[]')

  local profile_dir
  for profile_dir in "${profile_dirs[@]}"; do
    [[ -z "$profile_dir" ]] && continue

    local profile_name profile_email win_id
    profile_name=$(printf '%s' "$fp" | jq -r --arg d "$profile_dir" '.catalog[$d].name // $d')
    profile_email=$(printf '%s' "$fp" | jq -r --arg d "$profile_dir" '.catalog[$d].user_name // ""')
    win_id=$(printf '%s' "$fp" | jq -r --arg d "$profile_dir" '.by_dir[$d] // ""')

    if [[ -z "$win_id" ]]; then
      printf 'PROFILE=%s EMAIL=%s UNREAD=0 DELTA=0 STATUS=window_not_found\n' \
        "$profile_name" "$profile_email"
      continue
    fi

    # Try each mail provider pattern
    local tab_id="" matched_idx=-1
    local i
    for ((i = 0; i < ${#CHROME_MAIL_PROVIDERS[@]}; i++)); do
      local provider="${CHROME_MAIL_PROVIDERS[$i]}"
      tab_id=$(chrome_tab_for_url "$win_id" "$provider" 2> /dev/null || true)
      if [[ -n "$tab_id" ]]; then
        matched_idx=$i
        break
      fi
    done

    if [[ -z "$tab_id" ]]; then
      printf 'PROFILE=%s EMAIL=%s UNREAD=0 DELTA=0 STATUS=tab_not_found\n' \
        "$profile_name" "$profile_email"
      continue
    fi

    # Rate guard before JS call
    if ! _chrome_js_rate_guard; then
      printf 'PROFILE=%s EMAIL=%s UNREAD=0 DELTA=0 STATUS=rate_capped\n' \
        "$profile_name" "$profile_email"
      continue
    fi

    # Read document.title
    local title
    title=$(chrome_js "$win_id" "$tab_id" "document.title" 2> /dev/null || true)
    if [[ -z "$title" ]]; then
      printf 'PROFILE=%s EMAIL=%s UNREAD=0 DELTA=0 STATUS=js_error\n' \
        "$profile_name" "$profile_email"
      continue
    fi

    # Extract unread count via matched provider's regex
    local re="${CHROME_MAIL_UNREAD_RE[$matched_idx]}"
    local unread=0
    if [[ "$title" =~ $re ]]; then
      unread="${BASH_REMATCH[1]}"
    fi

    # Compute delta against prior state
    local prior_unread=0
    prior_unread=$(printf '%s' "$prior_state" |
      jq -r --arg d "$profile_dir" '.inbox_counts[$d] // 0' 2> /dev/null || printf '0')
    local delta=$((unread - prior_unread))
    local delta_str
    if ((delta > 0)); then
      delta_str="+$delta"
    else
      delta_str="$delta"
    fi

    printf 'PROFILE=%s EMAIL=%s UNREAD=%d DELTA=%s STATUS=ok\n' \
      "$profile_name" "$profile_email" "$unread" "$delta_str"

    # Update new state
    new_counts=$(printf '%s' "$new_counts" | jq --arg d "$profile_dir" --argjson n "$unread" \
      '. + {($d): $n}')
  done

  # Write new state atomically (NFR-SNAP-2: 0600 perms)
  _chrome_workflow_state_ensure_dir || return 0
  local new_state tmp
  new_state=$(jq -n --arg ts "$timestamp" --argjson counts "$new_counts" \
    '{version: 1, last_inbox_check: $ts, inbox_counts: $counts}')
  tmp=$(mktemp "${state_path}.XXXXXX") || return 0
  (umask 077 && printf '%s' "$new_state" > "$tmp")
  mv -f "$tmp" "$state_path" 2> /dev/null || rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# v0.7.0 — chrome_snapshot <name>: save tab state to JSON (feature 004 US2)
# ---------------------------------------------------------------------------
# Saves current tabs of all profiled windows to
#   ~/.config/claude-mac-chrome/snapshots/<name>.json
# URL query strings and fragments are stripped (NFR-SNAP-1).
# Max 20 snapshots, oldest evicted FIFO with stderr notice (NFR-SNAP-7).
# File perms 0600, dir 0700 (NFR-SNAP-2).
chrome_snapshot() {
  local name="$1"
  [[ -z "$name" ]] && {
    _chrome_err "usage: chrome_snapshot <name>"
    return 1
  }
  _chrome_validate_snapshot_name "$name" || return 1
  _chrome_snapshot_ensure_dir || return 1

  local snap_dir
  snap_dir=$(_chrome_snapshot_dir)
  local snap_path="${snap_dir}/${name}.json"

  # FIFO eviction if at cap (NFR-SNAP-7)
  local snap_count
  snap_count=$(find "$snap_dir" -maxdepth 1 -name '*.json' -type f 2> /dev/null | wc -l | tr -d ' ')
  if ((snap_count >= 20)) && [[ ! -f "$snap_path" ]]; then
    local oldest
    oldest=$(find "$snap_dir" -maxdepth 1 -name '*.json' -type f -exec stat -f '%m %N' {} + 2> /dev/null |
      sort -n | head -1 | awk '{print $2}')
    if [[ -n "$oldest" ]]; then
      _chrome_warn "snapshot cap reached (20); evicting oldest: $(basename "$oldest")"
      rm -f "$oldest"
    fi
  fi

  # Fetch all windows with their tabs in one AppleScript call per window
  local fp
  fp=$(chrome_fingerprint_cached)
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local profiles_json="[]"
  local -a profile_dirs
  mapfile -t profile_dirs < <(printf '%s' "$fp" | jq -r '.by_dir | keys[]')

  local profile_dir
  for profile_dir in "${profile_dirs[@]}"; do
    [[ -z "$profile_dir" ]] && continue
    local win_id profile_name
    win_id=$(printf '%s' "$fp" | jq -r --arg d "$profile_dir" '.by_dir[$d] // ""')
    profile_name=$(printf '%s' "$fp" | jq -r --arg d "$profile_dir" '.catalog[$d].name // $d')
    [[ -z "$win_id" ]] && continue

    # Fetch all tabs of this window — URLs and titles
    local tabs_raw
    tabs_raw=$(
      osascript 2> /dev/null << APPLESCRIPT
tell application "Google Chrome"
  try
    set output to ""
    set theTabs to tabs of window id "$win_id"
    repeat with t in theTabs
      set output to output & (URL of t) & tab & (title of t) & linefeed
    end repeat
    return output
  end try
end tell
APPLESCRIPT
    )

    # Parse tabs, strip query strings, build JSON array
    local tabs_json="[]"
    local idx=0
    while IFS=$'\t' read -r url title; do
      [[ -z "$url" ]] && continue
      local stripped_url
      stripped_url=$(_chrome_strip_url_query "$url")
      tabs_json=$(printf '%s' "$tabs_json" | jq --arg url "$stripped_url" --arg title "$title" --argjson idx "$idx" \
        '. + [{url: $url, title: $title, index: $idx}]')
      idx=$((idx + 1))
    done <<< "$tabs_raw"

    profiles_json=$(printf '%s' "$profiles_json" | jq \
      --arg dir "$profile_dir" --arg name "$profile_name" --arg wid "$win_id" --argjson tabs "$tabs_json" \
      '. + [{profile_dir: $dir, profile_name: $name, window_id: $wid, tabs: $tabs}]')
  done

  local snap_json
  snap_json=$(jq -n --arg name "$name" --arg ts "$timestamp" --argjson profiles "$profiles_json" \
    '{name: $name, created_at: $ts, profiles: $profiles}')

  # Atomic write with 0600 perms
  local tmp
  tmp=$(mktemp "${snap_path}.XXXXXX") || {
    _chrome_err "mktemp failed"
    return 1
  }
  (umask 077 && printf '%s' "$snap_json" > "$tmp")
  mv -f "$tmp" "$snap_path" || {
    rm -f "$tmp"
    _chrome_err "snapshot write failed"
    return 1
  }

  local tab_total
  tab_total=$(printf '%s' "$snap_json" | jq '[.profiles[].tabs | length] | add // 0')
  printf 'Saved snapshot %s: %d profiles, %d tabs\n' "$name" "${#profile_dirs[@]}" "$tab_total"
}

# ---------------------------------------------------------------------------
# v0.7.0 — chrome_restore <name>: restore tabs from snapshot (feature 004 US2)
# ---------------------------------------------------------------------------
# Emits per-profile status on stdout. URL scheme allowlist enforced
# (NFR-SNAP-4). Missing profiles skipped with warning. Staleness warned > 7d.
chrome_restore() {
  local name="$1"
  [[ -z "$name" ]] && {
    _chrome_err "usage: chrome_restore <name>"
    return 1
  }
  _chrome_validate_snapshot_name "$name" || return 1

  local snap_path
  snap_path="$(_chrome_snapshot_dir)/${name}.json"
  [[ ! -f "$snap_path" ]] && {
    _chrome_err "snapshot not found: $name"
    return 1
  }

  # Staleness warning (NFR-SNAP-6)
  local created_at
  created_at=$(jq -r '.created_at // ""' "$snap_path")
  if [[ -n "$created_at" ]]; then
    local created_epoch now_epoch age_days
    created_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$created_at" +%s 2> /dev/null || printf '0')
    now_epoch=$(date +%s)
    age_days=$(((now_epoch - created_epoch) / 86400))
    if ((age_days > 7)); then
      _chrome_warn "snapshot is $age_days days old (created $created_at)"
    fi
  fi

  # Current catalog for profile existence check
  local catalog
  catalog=$(chrome_profiles_catalog)

  # Iterate snapshot profiles
  local profile_count
  profile_count=$(jq '.profiles | length' "$snap_path")
  local i
  for ((i = 0; i < profile_count; i++)); do
    local profile_dir profile_name
    profile_dir=$(jq -r --argjson i "$i" '.profiles[$i].profile_dir' "$snap_path")
    profile_name=$(jq -r --argjson i "$i" '.profiles[$i].profile_name' "$snap_path")

    # Skip missing profiles (spec clarification Q2)
    local exists
    exists=$(printf '%s' "$catalog" | jq -r --arg d "$profile_dir" 'has($d)')
    if [[ "$exists" != "true" ]]; then
      printf 'PROFILE=%s STATUS=profile_missing TABS=0\n' "$profile_name"
      _chrome_warn "profile $profile_dir no longer exists — skipping"
      continue
    fi

    # Find window for profile
    local win_id
    win_id=$(chrome_window_for "$profile_dir" || true)
    if [[ -z "$win_id" ]]; then
      printf 'PROFILE=%s STATUS=window_not_found TABS=0\n' "$profile_name"
      continue
    fi

    # Iterate tabs, validate scheme, open
    local tab_count opened=0 rejected=0
    tab_count=$(jq --argjson i "$i" '.profiles[$i].tabs | length' "$snap_path")
    local j
    for ((j = 0; j < tab_count; j++)); do
      local url
      url=$(jq -r --argjson i "$i" --argjson j "$j" '.profiles[$i].tabs[$j].url' "$snap_path")
      # URL scheme allowlist (NFR-SNAP-4)
      if [[ ! "$url" =~ ^https?:// ]]; then
        _chrome_warn "rejecting non-http(s) URL from snapshot: ${url:0:60}"
        rejected=$((rejected + 1))
        continue
      fi
      if chrome_new_tab "$win_id" "$url" > /dev/null 2>&1; then
        opened=$((opened + 1))
      fi
    done
    printf 'PROFILE=%s STATUS=ok OPENED=%d REJECTED=%d\n' "$profile_name" "$opened" "$rejected"
  done
}

# ---------------------------------------------------------------------------
# v0.8.0 — Safe DOM Action Primitives (feature 005)
# ---------------------------------------------------------------------------
#
# CRITICAL: This section implements the safety gauntlet that makes the
# "accidental Proton 1mo purchase" incident architecturally impossible.
# Every mutating action MUST pass through _chrome_safety_gauntlet() before
# any event is dispatched. Partial-safety implementations are FORBIDDEN —
# if any helper is missing or fails, the action is blocked, not allowed.
# See spec 005-safe-dom-actions for the 53 NFRs enforced here.

# URL blocklist (readonly, NOT overridable) — NFR-SR-2
readonly -a CHROME_URL_BLOCKLIST=(
  "*/checkout*"
  "*/payment*"
  "*/billing*"
  "*/subscribe*"
  "*/upgrade*"
  "*/cart/*"
  "*/gp/buy/*"
  "*checkout.stripe.com/*"
  "*.paypal.com/checkout/*"
  "*buy.stripe.com/*"
  "*pay.google.com/*"
  "*account.proton.me/*upgrade*"
  "*account.proton.me/*dashboard*"
  "*accounts.google.com/signin*"
)

# Check if a URL matches any blocklist pattern. Returns 0 (match/blocked),
# 1 (clear). Uses `[[ == pattern ]]` which is consistent across bash 3.2
# (macOS system bash) through 5.3 regardless of shell option state.
_chrome_check_url_blocklist() {
  local url="$1" pattern
  for pattern in "${CHROME_URL_BLOCKLIST[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$url" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

# Audit log path (XDG-state, mode 0600, dir 0700) — NFR-SR-6
_chrome_audit_log_path() {
  printf '%s' "${HOME}/.local/state/claude-mac-chrome/action-audit.jsonl"
}

_chrome_audit_ensure_dir() {
  local dir="${HOME}/.local/state/claude-mac-chrome"
  if [[ -L "$dir" ]]; then
    _chrome_warn "Audit log directory is a symlink — refusing"
    return 1
  fi
  (umask 077 && mkdir -p "$dir") || return 1
}

# --- Rotation + append-only enforcement (NFR-SR-V2-16, NFR-SR-V2-AUDIT-ROT) ---
# Threshold: 10 MiB default, overridable via CHROME_AUDIT_ROTATE_BYTES for tests.
# Lock: mkdir-based mutex (atomic on POSIX, works without flock(1) on macOS).
# Append-only: chflags uappnd on Darwin (overridable via CHROME_AUDIT_APPEND_ONLY=0).

_chrome_audit_rotate_threshold() {
  printf '%d' "${CHROME_AUDIT_ROTATE_BYTES:-10485760}"
}

_chrome_audit_size() {
  local path="$1"
  [[ -f "$path" ]] || { printf '%d' 0; return; }
  wc -c < "$path" 2> /dev/null | tr -d ' '
}

_chrome_audit_lock_dir() {
  printf '%s' "${HOME}/.local/state/claude-mac-chrome/.rotate.lock"
}

_chrome_audit_lock() {
  local dir
  dir=$(_chrome_audit_lock_dir)
  local i=0
  while ! mkdir "$dir" 2> /dev/null; do
    i=$((i + 1))
    [[ $i -gt 50 ]] && return 1
    sleep 0.1
  done
  return 0
}

_chrome_audit_unlock() {
  rmdir "$(_chrome_audit_lock_dir)" 2> /dev/null || true
}

_chrome_audit_set_append_only() {
  [[ "${CHROME_AUDIT_APPEND_ONLY:-1}" == "1" ]] || return 0
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  chflags uappnd "$1" 2> /dev/null || true
}

_chrome_audit_clear_append_only() {
  [[ "${CHROME_AUDIT_APPEND_ONLY:-1}" == "1" ]] || return 0
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  chflags nouappnd "$1" 2> /dev/null || true
}

_chrome_audit_rotate_if_needed() {
  local log_path="$1"
  [[ -f "$log_path" ]] || return 0
  local size threshold
  size=$(_chrome_audit_size "$log_path")
  threshold=$(_chrome_audit_rotate_threshold)
  [[ "$size" -ge "$threshold" ]] || return 0

  # Contention → skip; next writer will retry. Never block the audit path.
  _chrome_audit_lock || return 0

  # Double-check under lock: a peer writer may have rotated already.
  size=$(_chrome_audit_size "$log_path")
  if [[ "$size" -ge "$threshold" ]]; then
    local rotated="${log_path}.1"
    _chrome_audit_clear_append_only "$log_path"
    if [[ -f "$rotated" ]]; then
      _chrome_audit_clear_append_only "$rotated"
      rm -f "$rotated" 2> /dev/null
    fi
    mv -f "$log_path" "$rotated" 2> /dev/null
    (umask 077 && : > "$log_path")
    _chrome_audit_set_append_only "$rotated"
    _chrome_audit_set_append_only "$log_path"
  fi
  _chrome_audit_unlock
}

# Append one JSONL entry to the audit log. Per NFR-SR-V2-14 (JSON-encoded
# control char sanitization via jq --arg) + NFR-SR-V2-16 (chflags append-only)
# + NFR-SR-V2-AUDIT-ROT (size-triggered single-slot rotation under mkdir lock).
_chrome_audit_append() {
  # Args: action outcome url selector element_text reason phase
  local action="$1" outcome="$2" url="$3" selector="$4"
  local element_text="${5:-}" reason="${6:-}" phase="${7:-pre_execute}"

  _chrome_audit_ensure_dir || return 1
  local log_path
  log_path=$(_chrome_audit_log_path)

  # Create with 0600 on first write, then mark append-only.
  if [[ ! -f "$log_path" ]]; then
    (umask 077 && : > "$log_path")
    _chrome_audit_set_append_only "$log_path"
  fi

  _chrome_audit_rotate_if_needed "$log_path"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # jq --arg handles all control char escaping + UTF-8 (NFR-SR-V2-14)
  local line
  line=$(jq -cn \
    --arg ts "$timestamp" \
    --arg action "$action" \
    --arg outcome "$outcome" \
    --arg url "$url" \
    --arg selector "$selector" \
    --arg element_text "$element_text" \
    --arg reason "$reason" \
    --arg phase "$phase" \
    '{timestamp: $ts, action: $action, outcome: $outcome, url: $url,
      selector: $selector, element_text: $element_text, reason: $reason,
      phase: $phase}')

  printf '%s\n' "$line" >> "$log_path"
}

# Prompt injection scanner — NFR-SR-11.
# Scans text for instruction-like substrings that could manipulate downstream
# Claude reasoning. Returns 0 if clean, 1 if injection suspected.
_chrome_prompt_injection_scan() {
  local text="$1"
  [[ -z "$text" ]] && return 0
  # Case-insensitive match against known injection patterns
  local lc
  lc=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
  local patterns=(
    "ignore previous"
    "ignore all previous"
    "you are now"
    "you're now"
    "system:"
    "assistant:"
    "<|"
    "[inst]"
    "### system"
    "<system>"
    "</system>"
    "jailbreak"
    "dan mode"
  )
  local p
  for p in "${patterns[@]}"; do
    if [[ "$lc" == *"$p"* ]]; then
      return 1
    fi
  done
  return 0
}

# Domain allowlist check — NFR-SR-8, NFR-SR-V2-18 (permissiveness ceiling).
# If CHROME_LIB_ALLOWED_DOMAINS is set, actions on non-matching domains fail.
# Returns 0 if allowed (or no allowlist set), 1 if not allowed.
_chrome_check_domain_allowlist() {
  local url="$1"
  local allowlist="${CHROME_LIB_ALLOWED_DOMAINS:-}"
  [[ -z "$allowlist" ]] && return 0 # No allowlist = unrestricted

  # NFR-SR-V2-18: ceiling — reject wildcards and bare TLDs
  case "$allowlist" in
    "*" | ".")
      _chrome_err "CHROME_LIB_ALLOWED_DOMAINS=$allowlist is too permissive — refusing (NFR-SR-V2-18)"
      return 1
      ;;
  esac

  # Extract hostname from URL
  local host
  host="${url#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')

  # Parse comma-separated allowlist, check each entry as domain-suffix match
  local IFS_save="$IFS"
  IFS=','
  local entry
  for entry in $allowlist; do
    entry=$(printf '%s' "$entry" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    [[ -z "$entry" ]] && continue
    # Reject bare TLDs (single label)
    if [[ "$entry" != *.* ]]; then
      IFS="$IFS_save"
      _chrome_err "CHROME_LIB_ALLOWED_DOMAINS entry '$entry' is a bare TLD — refusing"
      return 1
    fi
    # Domain-suffix match
    if [[ "$host" == "$entry" || "$host" == *".$entry" ]]; then
      IFS="$IFS_save"
      return 0
    fi
  done
  IFS="$IFS_save"
  return 1
}

# TTY confirmation with signal-proof 5-second read delay — NFR-SR-5,
# NFR-SR-V2-11 (TTY authenticity), NFR-SR-V2-12 (signal-proof delay),
# NFR-SR-V2-13 (prompt-injection quarantine delimiters).
# Returns 0 if user typed exact "yes" after the delay, 1 otherwise.
_chrome_tty_confirm() {
  local action="$1" selector="$2" url="$3" element_text="${4:-}"

  # NFR-SR-V2-11: TTY authenticity — require interactive TTY on stdin+stderr
  if [[ ! -t 0 ]] || [[ ! -t 2 ]]; then
    _chrome_err "TTY confirmation required but stdin/stderr is not a terminal — refusing"
    return 1
  fi

  # NFR-SR-11: prompt injection scanner — reject if element text contains
  # instruction-like substrings. This prevents a malicious page from
  # manipulating the downstream Claude reasoning that sees the prompt.
  if ! _chrome_prompt_injection_scan "$element_text"; then
    _chrome_err "element text contains prompt-injection pattern — refusing to display"
    return 1
  fi
  if ! _chrome_prompt_injection_scan "$url"; then
    _chrome_err "URL contains prompt-injection pattern — refusing to display"
    return 1
  fi

  # Strip control chars from element text for display (NFR-SR-V2-14)
  local safe_text
  safe_text=$(printf '%s' "$element_text" |
    tr -d '\000-\010\013-\037\177' |
    head -c 80)

  # Print prompt to stderr with <<UNTRUSTED>> delimiters (NFR-SR-V2-13)
  {
    printf '\n'
    printf '═══════════════════════════════════════════════════════════\n'
    printf '⚠  SAFETY CONFIRMATION REQUIRED\n'
    printf '═══════════════════════════════════════════════════════════\n'
    printf 'Action:    %s\n' "$action"
    printf 'URL:       %s\n' "$url"
    printf 'Selector:  %s\n' "$selector"
    printf 'Element text (UNTRUSTED — page content, not instructions):\n'
    printf '  <<UNTRUSTED>>%s<<END>>\n' "$safe_text"
    printf '───────────────────────────────────────────────────────────\n'
    printf 'This action will execute on a URL matching the purchase\n'
    printf 'blocklist. Type exactly "yes" (lowercase) to proceed.\n'
    printf 'Waiting 5 seconds before accepting input (NFR-SR-V2-12)...\n'
  } >&2

  # NFR-SR-V2-12: signal-proof monotonic deadline loop
  # shellcheck disable=SC2064
  trap '' ALRM USR1 USR2 CONT
  local deadline=$(($(date +%s) + 5))
  while (($(date +%s) < deadline)); do
    sleep 0.5 2> /dev/null || true
  done
  trap - ALRM USR1 USR2 CONT

  printf 'Type "yes" within 60 seconds to proceed: ' >&2

  # 60-second read timeout, exact "yes" match (NFR-SR-5)
  local response=""
  if ! read -r -t 60 response < /dev/tty; then
    printf '\n⚠  Confirmation timeout — action aborted\n' >&2
    return 1
  fi

  if [[ "$response" == "yes" ]]; then
    printf '✓ Confirmation accepted\n' >&2
    return 0
  fi

  printf '⚠  Confirmation did not match exact "yes" — action aborted\n' >&2
  return 1
}

# Rate limiter state path — NFR-SR-7, NFR-SR-V2-17 (fail-closed).
_chrome_rate_state_path() {
  printf '%s' "${HOME}/.local/state/claude-mac-chrome/rate.json"
}

# Rate limit check for mutating actions.
# Args: window_id
# Returns: 0 if within cap, 1 if rate-limited.
# Per NFR-SR-7: max 10 per 10s per window, 60 per 60s global.
# Per NFR-SR-V2-17: fail-closed on missing/corrupt/wrong-owner state.
_chrome_rate_check() {
  local window_id="$1"
  [[ -z "$window_id" ]] && return 1

  local state_path
  state_path=$(_chrome_rate_state_path)

  # Ensure state directory (reuse audit dir setup)
  _chrome_audit_ensure_dir || return 1

  # Initialize state file if missing — creates empty, 0600 perms.
  # This is NOT "silent re-init after corruption" (forbidden by NFR-SR-V2-17);
  # first-ever initialization on a fresh install is allowed.
  if [[ ! -f "$state_path" ]]; then
    (umask 077 && printf '%s' '{"version":1,"events":{},"global":[]}' > "$state_path")
  fi

  # Fail-closed checks
  if [[ ! -r "$state_path" ]]; then
    _chrome_err "rate state unreadable — refusing (NFR-SR-V2-17)"
    return 1
  fi
  # Use /usr/bin/stat (BSD syntax) explicitly — nix-darwin may have GNU
  # stat in PATH which uses different flags. Per NFR-SR-V2-17, fail-closed.
  local file_uid current_uid
  file_uid=$(/usr/bin/stat -f%u "$state_path" 2> /dev/null || printf '')
  current_uid=$(id -u)
  if [[ -z "$file_uid" ]]; then
    _chrome_err "cannot stat rate state file — refusing"
    return 1
  fi
  if [[ "$file_uid" != "$current_uid" ]]; then
    _chrome_err "rate state owned by uid $file_uid, current $current_uid — refusing"
    return 1
  fi
  # Check mtime is not in the future (clock skew or tamper)
  local now file_mtime
  now=$(date +%s)
  file_mtime=$(/usr/bin/stat -f%m "$state_path" 2> /dev/null || printf '')
  if [[ -z "$file_mtime" ]]; then
    _chrome_err "cannot read rate state mtime — refusing"
    return 1
  fi
  if ((file_mtime > now + 60)); then
    _chrome_err "rate state mtime in the future — refusing"
    return 1
  fi

  # Parse state — corruption = refuse
  local state
  if ! state=$(jq -c . "$state_path" 2> /dev/null); then
    _chrome_err "rate state corrupt JSON — refusing (NFR-SR-V2-17)"
    return 1
  fi
  local version
  version=$(printf '%s' "$state" | jq -r '.version // 0')
  if [[ "$version" != "1" ]]; then
    _chrome_err "rate state schema version $version != 1 — refusing"
    return 1
  fi

  # Compute cutoffs
  local now_ms window_cutoff global_cutoff
  now_ms=$((now * 1000))
  window_cutoff=$((now_ms - 10000)) # 10s
  global_cutoff=$((now_ms - 60000)) # 60s

  # Prune old events + check caps
  # Events for this window: count entries >= window_cutoff
  # Global: count entries >= global_cutoff
  local window_count global_count
  window_count=$(printf '%s' "$state" | jq --arg w "$window_id" --argjson cut "$window_cutoff" \
    '[(.events[$w] // []) | .[] | select(. >= $cut)] | length')
  global_count=$(printf '%s' "$state" | jq --argjson cut "$global_cutoff" \
    '[.global[] | select(. >= $cut)] | length')

  if ((window_count >= 10)); then
    _chrome_warn "rate limit: window $window_id has $window_count events in last 10s (cap 10)"
    return 1
  fi
  if ((global_count >= 60)); then
    _chrome_warn "rate limit: global $global_count events in last 60s (cap 60)"
    return 1
  fi

  # Within cap — append current timestamp and prune old events, write atomically
  local new_state tmp
  new_state=$(printf '%s' "$state" | jq -c \
    --arg w "$window_id" --argjson now "$now_ms" \
    --argjson wcut "$window_cutoff" --argjson gcut "$global_cutoff" \
    '.events[$w] = [((.events[$w] // []) | .[] | select(. >= $wcut))] + [$now]
     | .global = [(.global[] | select(. >= $gcut))] + [$now]')
  tmp=$(mktemp "${state_path}.XXXXXX") || return 1
  (umask 077 && printf '%s' "$new_state" > "$tmp")
  mv -f "$tmp" "$state_path" 2> /dev/null || {
    rm -f "$tmp"
    return 1
  }
  return 0
}

# Load the multi-locale trigger lexicon. Per NFR-SR-V2-1.
# Returns a regex alternation on stdout. Cached after first load.
_CHROME_LEXICON_CACHE=""
_chrome_load_trigger_lexicon() {
  if [[ -n "$_CHROME_LEXICON_CACHE" ]]; then
    printf '%s' "$_CHROME_LEXICON_CACHE"
    return 0
  fi
  local lexicon_path="${BASH_SOURCE[0]%/*}/lexicon/triggers.txt"
  if [[ ! -f "$lexicon_path" ]]; then
    _chrome_err "Lexicon file not found at $lexicon_path — refusing to run safety check"
    return 1
  fi
  # Strip comments, blank lines, escape regex metachars, join with |
  local tokens
  tokens=$(grep -vE '^\s*(#|$)' "$lexicon_path" |
    sed 's/[][(){}.*+?^$|\\]/\\&/g' |
    tr '\n' '|' |
    sed 's/|$//')
  _CHROME_LEXICON_CACHE="$tokens"
  printf '%s' "$tokens"
}

# Safely JSON-stringify a shell string for embedding as a JS string literal.
# Per NFR-JS-V2-1 — prevents "); evil(); // injection.
_chrome_json_stringify_sh() {
  local str="$1"
  printf '%s' "$str" | jq -Rs .
}

# Build the safety check JS that runs INSIDE the page.
# Inputs: selector (JSON-stringified), lexicon regex (JSON-stringified).
# Returns: JS source code as a single-line string.
# The JS returns a JSON envelope: {ok, blocked_reason?, element_found?, element_text?, url, ...}
_chrome_safety_check_js() {
  local sel_json="$1" lex_json="$2"
  cat << JSEOF
(function(){
  try {
    const _QS = document.querySelector.bind(document);
    const _GCS = window.getComputedStyle.bind(window);
    const sel = ${sel_json};
    const lexicon = ${lex_json};
    const lex_re = new RegExp("\\\\b(" + lexicon + ")\\\\b", "i");

    const result = {
      ok: false,
      url: document.location.href,
      ready_state: document.readyState,
      title: document.title,
      element_found: false,
      element_text: "",
      blocked_reason: null,
      fired_rail_trace: []
    };
    const _fire = function(rail) { result.fired_rail_trace.push(rail); };

    // NFR-SR-V2-2: script-confusables fold (Cyrillic / Greek / Armenian Latin-lookalikes)
    // plus zero-width + BiDi override + combining-mark strip. Covers NFKC blind spot
    // where distinct-script codepoints (Cyrillic \\u0430 "a", Greek \\u03BF "o", etc.)
    // render visually identical to Latin but never decompose via NFKC.
    const _CONFUSABLES_FOLD = {
      "\\u0430":"a","\\u0435":"e","\\u043E":"o","\\u0440":"p","\\u0441":"c","\\u0443":"y","\\u0445":"x",
      "\\u0456":"i","\\u0458":"j","\\u0455":"s","\\u0501":"d","\\u051B":"q","\\u051D":"w","\\u0451":"e",
      "\\u049B":"k","\\u04CF":"i","\\u0433":"r","\\u0434":"d","\\u0432":"b","\\u043A":"k","\\u043C":"m",
      "\\u043D":"h","\\u0442":"t","\\u0454":"e",
      "\\u0131":"i","\\u0261":"g",
      "\\u0410":"a","\\u0412":"b","\\u0415":"e","\\u041A":"k","\\u041C":"m","\\u041D":"h","\\u041E":"o",
      "\\u0420":"p","\\u0421":"c","\\u0422":"t","\\u0425":"x","\\u0423":"y","\\u0405":"s","\\u0406":"i",
      "\\u0408":"j","\\u04AE":"y","\\u04C0":"i",
      "\\u03B1":"a","\\u03BF":"o","\\u03C1":"p","\\u03BD":"v","\\u03B9":"i","\\u03BA":"k","\\u03B7":"n",
      "\\u03B5":"e","\\u03C7":"x","\\u03C5":"u","\\u03BC":"u","\\u03C4":"t",
      "\\u0391":"a","\\u0392":"b","\\u0395":"e","\\u0396":"z","\\u0397":"h","\\u0399":"i","\\u039A":"k",
      "\\u039C":"m","\\u039D":"n","\\u039F":"o","\\u03A1":"p","\\u03A4":"t","\\u03A5":"y","\\u03A7":"x",
      "\\u0561":"a","\\u0578":"n","\\u057D":"u","\\u057C":"n","\\u0585":"o","\\u0581":"g","\\u0566":"q",
      "\\u0570":"h","\\u0574":"u","\\u057A":"u"
    };
    function _foldConfusables(s) {
      if (!s) return "";
      // NFKD decomposes precomposed chars (café → cafe+́) so we can strip the
      // combining marks. NFKC would re-compose and defeat the strip.
      try { s = s.normalize("NFKD"); } catch (_) {}
      // Strip combining marks, zero-width, BiDi overrides, BOM, invisible separators
      s = s.replace(/[\\u0300-\\u036F\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u2064\\uFEFF]/g, "");
      let out = "";
      for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (c.charCodeAt(0) < 0x80) { out += c; continue; }
        out += _CONFUSABLES_FOLD[c] || c;
      }
      return out;
    }

    _fire("element_lookup");
    const el = _QS(sel);
    if (!el) {
      result.blocked_reason = "element_not_found";
      return JSON.stringify(result);
    }
    result.element_found = true;

    // Gather text from: textContent UNION innerText UNION shadow DOM UNION ::before/::after
    // NFR-SR-V2-7, NFR-SR-V2-8, NFR-SR-V2-9.
    function gatherAllText(node, depth) {
      if (!node || depth > 10) return "";
      let parts = [];
      try { parts.push(node.textContent || ""); } catch(_) {}
      try { parts.push(node.innerText || ""); } catch(_) {}
      // CSS pseudo-element content
      try {
        const before = _GCS(node, "::before").content;
        const after = _GCS(node, "::after").content;
        if (before && before !== "none" && before !== "normal") parts.push(before.replace(/^["']|["']$/g, ""));
        if (after && after !== "none" && after !== "normal") parts.push(after.replace(/^["']|["']$/g, ""));
      } catch(_) {}
      // Recursive shadow DOM descent (open roots only)
      try {
        if (node.shadowRoot && node.shadowRoot.mode === "open") {
          const shadowEls = node.shadowRoot.querySelectorAll("*");
          for (let i = 0; i < shadowEls.length && i < 100; i++) {
            parts.push(gatherAllText(shadowEls[i], depth + 1));
          }
        }
      } catch(_) {}
      return parts.join(" ");
    }

    const raw_text = gatherAllText(el, 0);
    // NFR-SR-V2-2: full script-confusables fold (_foldConfusables handles NFKC,
    // zero-width / BiDi / combining strip, and Cyrillic/Greek/Armenian fold).
    const norm_text = _foldConfusables(raw_text);
    result.element_text = norm_text.slice(0, 200);

    // 3-ancestor walk checking text + exhaustive attribute list (NFR-SR-V2-10)
    const attrs_to_check = [
      "aria-label", "aria-labelledby", "title", "name", "placeholder", "alt",
      "data-testid", "data-action"
    ];
    let node = el;
    _fire("ancestor_text_walk");
    for (let depth = 0; depth < 3 && node; depth++) {
      // Text check using full gatherAllText (includes shadow DOM + ::before/::after)
      const node_text = _foldConfusables(gatherAllText(node, 0));
      if (lex_re.test(node_text)) {
        result.blocked_reason = "purchase_button_text_depth_" + depth;
        return JSON.stringify(result);
      }
      // Attribute check
      if (node.getAttribute) {
        for (const attr of attrs_to_check) {
          const val = node.getAttribute(attr) || "";
          if (val && lex_re.test(_foldConfusables(val))) {
            result.blocked_reason = "purchase_button_attr_" + attr + "_depth_" + depth;
            return JSON.stringify(result);
          }
        }
      }
      node = node.parentElement;
    }

    // Payment field detection (NFR-SR-3)
    _fire("payment_field_lock");
    const payment_inputs = document.querySelectorAll(
      'input[autocomplete*="cc-"], input[name*="card"], input[name*="cvv"], input[name*="cvc"]'
    );
    if (payment_inputs.length > 0) {
      result.blocked_reason = "payment_field_lock";
      return JSON.stringify(result);
    }

    // Inert container check (NFR-JS-V2-8)
    _fire("inert_container");
    if (el.closest("template, dialog:not([open]), [inert]")) {
      result.blocked_reason = "inert_container";
      return JSON.stringify(result);
    }

    // Visibility check (NFR-JS-V2-4 partial — full predicate in v0.8.1)
    _fire("visibility");
    const cs = _GCS(el);
    if (cs.display === "none" || cs.visibility === "hidden" || parseFloat(cs.opacity) < 0.1) {
      result.blocked_reason = "not_visible";
      return JSON.stringify(result);
    }
    _fire("zero_dimensions");
    const rect = el.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) {
      result.blocked_reason = "zero_dimensions";
      return JSON.stringify(result);
    }

    // TOCTOU fingerprint (NFR-SR-V2-TOCTOU): lock the element's outerHTML hash
    // and bounding-rect snapshot so the dispatch step can detect DOM mutation
    // between safety-pass and click. FNV-1a 32-bit — integrity signal, not
    // cryptographic. outerHTML truncated to 5000 chars to bound the hash input.
    function _fnv1a(s) {
      let h = 0x811c9dc5;
      for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
      }
      return h.toString(16);
    }
    try {
      const _fp_rect = el.getBoundingClientRect();
      result.element_fingerprint = {
        tag: el.tagName || "",
        id: el.id || "",
        outerHTML_hash: _fnv1a((el.outerHTML || "").slice(0, 5000)),
        rect: {
          x: Math.round(_fp_rect.left),
          y: Math.round(_fp_rect.top),
          w: Math.round(_fp_rect.width),
          h: Math.round(_fp_rect.height)
        }
      };
    } catch (_) {
      result.element_fingerprint = null;
    }

    // All checks passed — action is allowed
    result.ok = true;
    return JSON.stringify(result);
  } catch (e) {
    return JSON.stringify({
      ok: false,
      blocked_reason: "js_error",
      error: String(e),
      stack: (e && e.stack || "").slice(0, 500)
    });
  }
})();
JSEOF
}

# chrome_click — the safety-gated click primitive.
# Usage: chrome_click <window_id> <tab_id> <selector> [--confirm-purchase=<text>] [--dry-run]
# Returns a JSON envelope on stdout. Exit 0 on success, non-zero on failure.
#
# SAFETY GAUNTLET ORDER (spec 005 NFR-SR-*):
# 1. URL blocklist check (T008) — NFR-SR-2
# 2. Inject safety check JS (T014) — NFR-SR-1, SR-3, SR-V2-1..10, JS-V2-3..8
# 3. If safe AND NOT dry-run, dispatch event.click() via AppleScript
# 4. Return JSON envelope in every case
chrome_click() {
  local win_id="$1" tab_id="$2" selector="$3"
  shift 3 || true
  local dry_run=0 confirm_purchase=""

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --confirm-purchase=*)
        confirm_purchase="${1#*=}"
        shift
        ;;
      *)
        _chrome_err "chrome_click: unknown flag $1"
        return 1
        ;;
    esac
  done

  if [[ -z "$win_id" || -z "$tab_id" || -z "$selector" ]]; then
    printf '{"ok":false,"error":"INVALID_ARGS","reason":"usage: chrome_click <win> <tab> <selector> [--dry-run] [--confirm-purchase=<text>]"}\n'
    return 2
  fi

  # Step 1: Read the current tab URL (authoritative Chrome state)
  local current_url
  current_url=$(chrome_tab_url "$win_id" "$tab_id" 2> /dev/null || printf '')
  if [[ -z "$current_url" ]]; then
    printf '{"ok":false,"error":"ELEMENT_NOT_FOUND","reason":"could_not_read_tab_url","window_id":"%s","tab_id":"%s"}\n' "$win_id" "$tab_id"
    return 3
  fi

  # Audit log: pre-execute entry
  _chrome_audit_append "click" "pending" "$current_url" "$selector" "" "" "pre_execute" 2> /dev/null || true

  # Step 1a: Domain allowlist check (NFR-SR-8, only if CHROME_LIB_ALLOWED_DOMAINS set)
  if ! _chrome_check_domain_allowlist "$current_url"; then
    _chrome_audit_append "click" "blocked" "$current_url" "$selector" "" "not_in_allowlist" "post_execute" 2> /dev/null || true
    printf '{"ok":false,"error":"NOT_ALLOWED_DOMAIN","reason":"url not in CHROME_LIB_ALLOWED_DOMAINS","url":%s}\n' \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  fi

  # Step 2: URL blocklist check (NFR-SR-2)
  if _chrome_check_url_blocklist "$current_url"; then
    if [[ -z "$confirm_purchase" ]]; then
      _chrome_audit_append "click" "blocked" "$current_url" "$selector" "" "url_blocklist" "post_execute" 2> /dev/null || true
      printf '{"ok":false,"error":"SAFETY_BLOCK","reason":"url_blocklist","url":%s,"hint":"pass --confirm-purchase=<exact-button-text> to override (requires TTY confirmation + 5s delay)"}\n' \
        "$(_chrome_json_stringify_sh "$current_url")"
      return 1
    fi
    # --confirm-purchase provided: require TTY confirmation with 5s signal-proof delay
    if ! _chrome_tty_confirm "click" "$selector" "$current_url" "$confirm_purchase"; then
      _chrome_audit_append "click" "blocked" "$current_url" "$selector" "$confirm_purchase" "tty_confirmation_denied" "post_execute" 2> /dev/null || true
      printf '{"ok":false,"error":"SAFETY_BLOCK","reason":"tty_confirmation_denied","url":%s}\n' \
        "$(_chrome_json_stringify_sh "$current_url")"
      return 1
    fi
    _chrome_audit_append "click" "tty_confirmed" "$current_url" "$selector" "$confirm_purchase" "user_typed_yes" "pre_execute" 2> /dev/null || true
  fi

  # Step 2a: Rate limit check (NFR-SR-7, NFR-SR-V2-17)
  if ! _chrome_rate_check "$win_id"; then
    _chrome_audit_append "click" "blocked" "$current_url" "$selector" "" "rate_limited" "post_execute" 2> /dev/null || true
    printf '{"ok":false,"error":"RATE_LIMITED","reason":"exceeded 10 actions/10s per window or 60/min global","url":%s}\n' \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  fi

  # Step 3: Load the multi-locale lexicon (required — fail closed if missing)
  local lexicon
  if ! lexicon=$(_chrome_load_trigger_lexicon); then
    printf '{"ok":false,"error":"SAFETY_BLOCK","reason":"lexicon_load_failed","hint":"lexicon/triggers.txt is missing — cannot safely evaluate action"}\n'
    return 1
  fi

  # Step 4: Build the safety check JS with parameterized inputs (NFR-JS-V2-1)
  local sel_json lex_json safety_js
  sel_json=$(_chrome_json_stringify_sh "$selector")
  lex_json=$(_chrome_json_stringify_sh "$lexicon")
  safety_js=$(_chrome_safety_check_js "$sel_json" "$lex_json")

  # Collapse to single line for chrome_js transport
  local safety_js_oneline
  safety_js_oneline=$(printf '%s' "$safety_js" | tr '\n' ' ')

  # Step 5: Inject the safety check
  local check_result
  check_result=$(chrome_js "$win_id" "$tab_id" "$safety_js_oneline" 2> /dev/null || printf '')
  if [[ -z "$check_result" ]]; then
    printf '{"ok":false,"error":"JS_ERROR","reason":"safety_check_returned_empty","url":%s}\n' \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  fi

  # Step 6: Parse the envelope
  local check_ok check_reason
  check_ok=$(printf '%s' "$check_result" | jq -r '.ok // false' 2> /dev/null || printf 'false')
  if [[ "$check_ok" != "true" ]]; then
    check_reason=$(printf '%s' "$check_result" | jq -r '.blocked_reason // "unknown"' 2> /dev/null || printf 'parse_error')
    local element_text
    element_text=$(printf '%s' "$check_result" | jq -r '.element_text // ""' 2> /dev/null || printf '')
    _chrome_audit_append "click" "blocked" "$current_url" "$selector" "$element_text" "$check_reason" "post_execute" 2> /dev/null || true
    printf '{"ok":false,"error":"SAFETY_BLOCK","reason":%s,"element_text":%s,"url":%s}\n' \
      "$(_chrome_json_stringify_sh "$check_reason")" \
      "$(_chrome_json_stringify_sh "$element_text")" \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  fi

  # Step 7: Safe to dispatch (unless dry-run)
  if ((dry_run)); then
    _chrome_audit_append "click" "dry_run" "$current_url" "$selector" "" "would_dispatch" "post_execute" 2> /dev/null || true
    printf '{"ok":true,"action":"click","dry_run":true,"selector":%s,"url":%s}\n' \
      "$(_chrome_json_stringify_sh "$selector")" \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 0
  fi

  # Step 8: Dispatch full pointer event sequence per NFR-JS-1.
  # `element.click()` alone is insufficient for React 18+/Vue 3 components
  # that listen on pointerdown. Full sequence: pointerdown → mousedown →
  # pointerup → mouseup → click, with coordinates from getBoundingClientRect
  # center. Includes element.isConnected verification (NFR-SR-V2-6),
  # elementFromPoint hit-test (NFR-JS-V2-5), and TOCTOU fingerprint compare
  # against the safety-check envelope (NFR-SR-V2-TOCTOU).
  local expected_fp
  expected_fp=$(printf '%s' "$check_result" | jq -c '.element_fingerprint // null' 2> /dev/null || printf 'null')
  local click_js
  click_js=$(
    cat << JSEOF
(function(){
  try {
    const _QS = document.querySelector.bind(document);
    const _GCS = window.getComputedStyle.bind(window);
    const _EFP = document.elementFromPoint.bind(document);
    const _EXPECTED_FP = ${expected_fp};
    function _fnv1a(s) {
      let h = 0x811c9dc5;
      for (let i = 0; i < s.length; i++) {
        h ^= s.charCodeAt(i);
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
      }
      return h.toString(16);
    }
    const el = _QS(${sel_json});
    if (!el) return JSON.stringify({ok:false,error:"element_vanished"});
    if (!el.isConnected) return JSON.stringify({ok:false,error:"element_detached"});
    if (el.disabled || el.getAttribute("aria-disabled") === "true") {
      return JSON.stringify({ok:false,error:"element_disabled"});
    }
    el.scrollIntoView({block:"center", inline:"center", behavior:"instant"});
    const rect = el.getBoundingClientRect();
    // TOCTOU drift check: recompute fingerprint, compare against safety snapshot.
    // Tag/id/outerHTML_hash are exact-match; rect allows 4px jitter for layout reflow.
    if (_EXPECTED_FP) {
      const _cur_fp = {
        tag: el.tagName || "",
        id: el.id || "",
        outerHTML_hash: _fnv1a((el.outerHTML || "").slice(0, 5000)),
        rect: {x: Math.round(rect.left), y: Math.round(rect.top),
               w: Math.round(rect.width), h: Math.round(rect.height)}
      };
      const drift = [];
      if (_cur_fp.tag !== _EXPECTED_FP.tag) drift.push("tag");
      if (_cur_fp.id !== _EXPECTED_FP.id) drift.push("id");
      if (_cur_fp.outerHTML_hash !== _EXPECTED_FP.outerHTML_hash) drift.push("outerHTML_hash");
      const er = _EXPECTED_FP.rect || {x:0,y:0,w:0,h:0};
      if (Math.abs(_cur_fp.rect.x - er.x) > 4 || Math.abs(_cur_fp.rect.y - er.y) > 4 ||
          Math.abs(_cur_fp.rect.w - er.w) > 4 || Math.abs(_cur_fp.rect.h - er.h) > 4) {
        drift.push("rect");
      }
      if (drift.length > 0) {
        return JSON.stringify({ok:false, error:"toctou_drift", drift:drift});
      }
    }
    if (rect.width < 1 || rect.height < 1) {
      return JSON.stringify({ok:false,error:"zero_dimensions"});
    }
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    if (cx < 0 || cy < 0 || cx >= window.innerWidth || cy >= window.innerHeight) {
      return JSON.stringify({ok:false,error:"out_of_viewport",cx:cx,cy:cy});
    }
    // Hit-test: verify the element at the target coords is actually our target
    // (defeats clickjacking overlays). NFR-JS-V2-5.
    const hit = _EFP(cx, cy);
    if (hit !== el && !el.contains(hit)) {
      return JSON.stringify({ok:false,error:"clickjack_suspected",hit_tag:(hit && hit.tagName)||"null"});
    }
    // Full pointer event sequence
    const opts = {bubbles:true, cancelable:true, view:window, button:0, clientX:cx, clientY:cy, pointerType:"mouse"};
    el.dispatchEvent(new PointerEvent("pointerdown", opts));
    el.dispatchEvent(new MouseEvent("mousedown", opts));
    el.dispatchEvent(new PointerEvent("pointerup", opts));
    el.dispatchEvent(new MouseEvent("mouseup", opts));
    const clickResult = el.dispatchEvent(new MouseEvent("click", opts));
    if (!clickResult) {
      return JSON.stringify({ok:false,error:"click_preventDefault_called"});
    }
    return JSON.stringify({ok:true, dispatched:"pointer_sequence"});
  } catch(e) {
    return JSON.stringify({ok:false,error:"dispatch_exception",message:String(e)});
  }
})();
JSEOF
  )
  # Collapse multi-line JS to single line for chrome_js transport
  local click_js_oneline
  click_js_oneline=$(printf '%s' "$click_js" | tr '\n' ' ')
  local click_result
  click_result=$(chrome_js "$win_id" "$tab_id" "$click_js_oneline" 2> /dev/null || printf '')

  if [[ "$click_result" == *'"ok":true'* ]]; then
    _chrome_audit_append "click" "ok" "$current_url" "$selector" "" "dispatched" "post_execute" 2> /dev/null || true
    printf '{"ok":true,"action":"click","selector":%s,"url":%s}\n' \
      "$(_chrome_json_stringify_sh "$selector")" \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 0
  elif [[ "$click_result" == *'"error":"toctou_drift"'* ]]; then
    local drift_fields
    drift_fields=$(printf '%s' "$click_result" | jq -c '.drift // []' 2> /dev/null || printf '[]')
    _chrome_audit_append "click" "blocked" "$current_url" "$selector" "" "toctou_drift" "post_execute" 2> /dev/null || true
    printf '{"ok":false,"error":"SAFETY_BLOCK","reason":"toctou_drift","drift":%s,"selector":%s,"url":%s}\n' \
      "$drift_fields" \
      "$(_chrome_json_stringify_sh "$selector")" \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  else
    _chrome_audit_append "click" "dispatch_failed" "$current_url" "$selector" "" "" "post_execute" 2> /dev/null || true
    printf '{"ok":false,"error":"CLICK_DISPATCH_FAILED","selector":%s,"url":%s}\n' \
      "$(_chrome_json_stringify_sh "$selector")" \
      "$(_chrome_json_stringify_sh "$current_url")"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# v0.8.0 — Read-only primitives (feature 005 US4, US5)
# ---------------------------------------------------------------------------

# chrome_query — read element text or attribute, READ-ONLY (no gauntlet).
# Usage: chrome_query <win> <tab> <selector> [--attribute <name>] [--deep]
# Returns JSON envelope: {ok, found, text?, attribute?, url}
chrome_query() {
  local win_id="$1" tab_id="$2" selector="$3"
  shift 3 || true
  local attribute="" deep=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --attribute)
        attribute="$2"
        shift 2
        ;;
      --attribute=*)
        attribute="${1#*=}"
        shift
        ;;
      --deep)
        deep=1
        shift
        ;;
      *)
        _chrome_err "chrome_query: unknown flag $1"
        return 1
        ;;
    esac
  done

  if [[ -z "$win_id" || -z "$tab_id" || -z "$selector" ]]; then
    printf '{"ok":false,"error":"INVALID_ARGS","reason":"usage: chrome_query <win> <tab> <selector> [--attribute name] [--deep]"}\n'
    return 2
  fi

  local sel_json attr_json
  sel_json=$(_chrome_json_stringify_sh "$selector")
  attr_json=$(_chrome_json_stringify_sh "$attribute")

  # Read-only query JS. Descends into open shadow roots if --deep.
  # NFR-JS-V2-3 realm pinning applied.
  local query_js
  query_js=$(
    cat << JSEOF
(function(){
  try {
    const _QS = document.querySelector.bind(document);
    const _QSA = document.querySelectorAll.bind(document);
    const sel = ${sel_json};
    const attr = ${attr_json};
    const deep = ${deep};

    function findDeep(root, selector, depth) {
      if (depth > 10) return null;
      try {
        const direct = root.querySelector(selector);
        if (direct) return direct;
      } catch(_) {}
      // Walk all elements and descend into shadow roots
      try {
        const all = root.querySelectorAll ? root.querySelectorAll("*") : [];
        for (let i = 0; i < all.length; i++) {
          const el = all[i];
          if (el.shadowRoot && el.shadowRoot.mode === "open") {
            const hit = findDeep(el.shadowRoot, selector, depth + 1);
            if (hit) return hit;
          }
        }
      } catch(_) {}
      return null;
    }

    const el = deep ? findDeep(document, sel, 0) : _QS(sel);
    if (!el) {
      return JSON.stringify({ok: true, found: false, url: document.location.href});
    }

    let value;
    if (attr) {
      value = el.getAttribute(attr);
    } else {
      value = (el.textContent || el.innerText || "").slice(0, 10000);
    }
    return JSON.stringify({
      ok: true,
      found: true,
      value: value,
      tag: el.tagName,
      url: document.location.href
    });
  } catch(e) {
    return JSON.stringify({ok: false, error: "query_exception", message: String(e)});
  }
})();
JSEOF
  )
  local query_js_oneline
  query_js_oneline=$(printf '%s' "$query_js" | tr '\n' ' ')

  local result
  result=$(chrome_js "$win_id" "$tab_id" "$query_js_oneline" 2> /dev/null || printf '')
  if [[ -z "$result" ]]; then
    printf '{"ok":false,"error":"JS_ERROR","reason":"query returned empty"}\n'
    return 1
  fi
  printf '%s\n' "$result"
}

# chrome_wait_for — poll for element to appear, host-side loop.
# Usage: chrome_wait_for <win> <tab> <selector> [--timeout ms] [--interval ms] [--deep]
# Default timeout 10000ms, interval 250ms, max 60000ms.
chrome_wait_for() {
  local win_id="$1" tab_id="$2" selector="$3"
  shift 3 || true
  local timeout_ms=10000 interval_ms=250 deep_flag=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --timeout)
        timeout_ms="$2"
        shift 2
        ;;
      --timeout=*)
        timeout_ms="${1#*=}"
        shift
        ;;
      --interval)
        interval_ms="$2"
        shift 2
        ;;
      --interval=*)
        interval_ms="${1#*=}"
        shift
        ;;
      --deep)
        deep_flag="--deep"
        shift
        ;;
      *)
        _chrome_err "chrome_wait_for: unknown flag $1"
        return 1
        ;;
    esac
  done

  if [[ -z "$win_id" || -z "$tab_id" || -z "$selector" ]]; then
    printf '{"ok":false,"error":"INVALID_ARGS","reason":"usage: chrome_wait_for <win> <tab> <selector> [--timeout ms] [--interval ms] [--deep]"}\n'
    return 2
  fi

  # Clamp per NFR-FR-7a
  if ((timeout_ms > 60000)); then timeout_ms=60000; fi
  if ((interval_ms < 100)); then interval_ms=100; fi

  local start_ms
  start_ms=$(date +%s000)
  local deadline_ms=$((start_ms + timeout_ms))
  local sleep_sec
  # bash doesn't do float math; use awk
  sleep_sec=$(awk "BEGIN { printf \"%.3f\", $interval_ms / 1000 }")

  while :; do
    local now_ms
    now_ms=$(date +%s000)
    if ((now_ms >= deadline_ms)); then
      local elapsed=$((now_ms - start_ms))
      printf '{"ok":false,"error":"TIMEOUT","found":false,"elapsed_ms":%d}\n' "$elapsed"
      return 1
    fi
    local result
    # shellcheck disable=SC2086
    result=$(chrome_query "$win_id" "$tab_id" "$selector" $deep_flag 2> /dev/null || printf '')
    if [[ -n "$result" ]]; then
      local found
      found=$(printf '%s' "$result" | jq -r '.found // false' 2> /dev/null || printf 'false')
      if [[ "$found" == "true" ]]; then
        local elapsed=$((now_ms - start_ms))
        printf '{"ok":true,"found":true,"elapsed_ms":%d}\n' "$elapsed"
        return 0
      fi
    fi
    sleep "$sleep_sec" 2> /dev/null || true
  done
}

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
    profile_urls)
      _chrome_err "profile_urls was removed in v0.4.0 (SNSS parser eliminated)"
      exit 1
      ;;
    check_inboxes) chrome_check_inboxes ;;
    snapshot) chrome_snapshot "$@" ;;
    restore) chrome_restore "$@" ;;
    register_window) chrome_register_window "$@" ;;
    unregister_window) chrome_unregister_window "$@" ;;
    click) chrome_click "$@" ;;
    query) chrome_query "$@" ;;
    wait_for) chrome_wait_for "$@" ;;
    _emit_safety_js)
      # Hidden CLI verb for test harness (feature 006 T006).
      # Usage: chrome-lib.sh _emit_safety_js <selector>
      # Emits the safety check JS to stdout with parameterized selector.
      # Not documented in public help. Test-only.
      _emit_sel="${1:-button}"
      _emit_sel_json=$(_chrome_json_stringify_sh "$_emit_sel")
      _emit_lex_json=$(_chrome_json_stringify_sh "$(_chrome_load_trigger_lexicon)")
      _chrome_safety_check_js "$_emit_sel_json" "$_emit_lex_json"
      unset _emit_sel _emit_sel_json _emit_lex_json
      ;;
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
