# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-04-06

### Added

- **Same-email profile disambiguation via SNSS Sessions/Tabs URL-set overlap.** When two or more Chrome profiles share the same signed-in Google account (e.g., one email but separate profiles for Personal Shopping / Personal Dev / Personal Research), the library now parses each profile's latest `Sessions/Tabs_<id>` file (Chrome's own per-profile session snapshot) via binary `strings` extraction, then scores each candidate profile by how much the live window's tab URLs overlap with the profile's saved URL set. The profile with the highest A-coverage score wins. Ties are broken by SNSS file mtime (most recently written wins). Validated via synthetic test with three collision profiles, 100% correct routing.
- `assignments` field in `chrome_fingerprint` output: per-window record of `{profile_dir, name, email, method, score}`. Method is one of `email_unique` (single email match), `url_overlap` (same-email disambiguation), `url_fallback` (no email signal, matched purely by URLs), or `no_signal` (couldn't assign).
- `chrome_profile_urls <profile_dir>` CLI command — dump the SNSS-extracted URL set for a given profile, for debugging same-email routing decisions.
- **Modern shell practices throughout:** `#!/usr/bin/env bash` shebang, `set -euo pipefail` in CLI entry point (not sourced), `[[ ]]` tests everywhere, full variable quoting, `readonly` for constants, `printf` instead of `echo` for structured output, `mktemp`-based atomic cache writes, consistent `_chrome_err` / `_chrome_warn` error reporters.
- `scripts/lint.sh` — contributor lint runner combining shfmt format check + shellcheck (style severity) + live smoke test (catalog parse, fingerprint parse, JS round-trip). Auto-fetches shfmt and shellcheck via `nix run nixpkgs#<pkg>` if not in PATH.
- `chrome_debug` output now shows the match method (`email (unique)` vs `URL overlap`) and confidence score for every matched window.

### Changed

- `chrome_fingerprint_cached` now writes the cache atomically via `mktemp` + `mv -f` to prevent corrupt reads during concurrent invocations.
- `CHROME_CACHE` now honors `$TMPDIR` if set, falling back to `/tmp`.
- All error output routed through `_chrome_err` with a `[chrome-lib]` prefix for easy grepping in logs.

### Verified

- **shellcheck clean** at `--severity=style` (stricter than the default `warning` level).
- **shfmt clean** with the project style (`-i 2 -ci -sr`).
- End-to-end smoke test passes on Pedro's actual 2-profile Chrome setup (`Personal` + `Study`) — email_unique path.
- Synthetic 3-profile same-email collision test passes — url_overlap path cleanly routes each window to the correct profile with 1.000 confidence.

## [0.2.0] — 2026-04-06

### Added

- **Authoritative profile catalog from Chrome's `Local State` file** — the library now reads `~/Library/Application Support/Google/Chrome/Local State` directly to enumerate every profile on the machine, with directory names, display names, signed-in Google account emails, and gaia names. Zero user configuration required.
- **Email extraction from tab titles** as the per-window identity signal. Every Google / Gmail / Drive / Classroom / ProtonMail / Fastmail tab has the signed-in email in its title. The library scans all tabs in all windows and matches emails against the catalog.
- **Multi-index window resolution via `chrome_window_for`** — accepts profile directory name, display name, email, any substring of any of those, or a role alias from an optional `~/.config/claude-mac-chrome/roles.json` file.
- **Optional role alias file** at `~/.config/claude-mac-chrome/roles.json` for mapping semantic roles (`work`, `school`, `personal`) to specific profiles.
- **`chrome-lib.sh catalog`** command — dumps the raw profile catalog.
- Structured fingerprint output with `by_dir`, `by_name`, `by_email`, `unknown`, and `catalog` keys.
- `docs/profile-detection.md` — deep reference on Local State format, email extraction heuristics, edge cases.

### Changed

- **`chrome_fingerprint` no longer uses hardcoded URL substring matching.** The 0.1.0 default fingerprints (flatnotes, classroom, etc.) are gone. The library now works deterministically on any macOS Chrome setup without configuration.
- **`chrome_debug` output format** redesigned to show both the Local State catalog and the matched windows in a tabular view.
- `SKILL.md` rewritten to document the new approach.
- `README.md` updated with the Local State + email extraction flow and comparison table.

### Removed

- Hardcoded personal URLs (`flatnotes.home301server.com.br`) from all default fingerprint logic. These were a privacy leak in 0.1.0 — the library now contains zero URLs specific to any individual user.
- `docs/fingerprints.md` — replaced by `docs/profile-detection.md` with the new approach.

### Fixed

- Windows with tabs not matching any hardcoded URL fingerprint are no longer silently labeled `other` — they're now matched by their Google account email automatically.

## [0.1.0] — 2026-04-06

### Added

- Initial release
- `chrome-multi-profile` skill with progressive-disclosure `SKILL.md`
- `chrome-lib.sh` library with stable-ID addressing via AppleScript
- URL substring fingerprint matching (superseded in 0.2.0)
- `/chrome-debug` slash command
- Zero dependencies (pure bash + osascript)
