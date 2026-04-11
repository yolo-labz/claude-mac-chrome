# Launch kit

Ready-to-paste content for distributing claude-mac-chrome across platforms. Each file targets one channel and is formatted for that channel's specific quirks (character limits, markdown flavor, posting convention).

## Files

| File | Channel | Auth needed | Status |
|---|---|---|---|
| [`reddit-r-claudecode.md`](reddit-r-claudecode.md) | Reddit r/ClaudeCode (also cross-post r/ClaudeAI) | Reddit account | ready to paste |
| [`hackernews-show-hn.md`](hackernews-show-hn.md) | Hacker News Show HN | HN account | ready to paste |
| [`blog-post.md`](blog-post.md) | dev.to / Medium / personal blog | platform account | ready to publish, has frontmatter for dev.to |
| [`twitter-thread.md`](twitter-thread.md) | Twitter / X | X account | 7-tweet thread, character-counted |
| `marketplace-form.md` (this file's "Anthropic submission" section below) | https://platform.claude.com/plugins/submit | Anthropic Console developer account | manual — see below |

## Anthropic official marketplace submission

The official `anthropics/claude-plugins-official` repo **auto-rejects external PRs** via a github-actions bot. The only path is the in-app submission form behind authentication.

### URLs (in order of preference)

1. https://platform.claude.com/plugins/submit (Claude Console — preferred)
2. https://claude.ai/settings/plugins/submit (currently 404-redirects to settings/general — may not be live yet)

### Prerequisites

- An Anthropic Console developer account (separate from a Claude.ai Pro/Max subscription). Sign up at https://platform.claude.com if you don't have one.
- The repo URL must be public and have a valid `.claude-plugin/plugin.json`. ✅ Done.
- A pinned commit SHA. Use the latest from `git rev-parse origin/main` on yolo-labz/claude-mac-chrome.

### Field values to paste

| Field | Value |
|---|---|
| Plugin name | `claude-mac-chrome` |
| Repo URL | `https://github.com/yolo-labz/claude-mac-chrome` |
| Pinned commit SHA | `c1055a93dee95e9a16547d8b5e1a795066c163f0` (or latest on `v1.0.0` tag) |
| Version | `1.0.0-rc1` (update to `1.0.0` after tag ceremony) |
| Category | `development` |
| License | MIT |
| Homepage | `https://github.com/yolo-labz/claude-mac-chrome` |
| Author name | Pedro Henrique Souza Balbino |
| Author email | pedrobalbino@proton.me |
| Author GitHub | phsb5321 |

### Short description (185 chars, fits typical form limits)

```
Professional Chrome automation for Claude Code on macOS. Deterministic multi-profile detection via Local State catalog + tab-title email extraction + SNSS URL-overlap disambiguation. Stable AppleScript IDs. Zero deps.
```

### Long description (free-text justification)

```
Existing Chrome automation tooling for Claude Code on macOS either uses ordinal indices (which suffer from z-order drift across multiple profiles) or CDP (which Chrome blocks on the default profile by Apple security policy).

claude-mac-chrome combines three deterministic signals — Chrome's own Local State catalog, tab-title email extraction, and SNSS Sessions/Tabs URL-set overlap for same-email disambiguation — to reliably route automation to the correct profile's window with stable string IDs that don't drift across z-order reorders, tab reorders, or focus changes.

Zero user configuration required. Zero dependencies (bash + osascript + python3 stdlib only). shellcheck + shfmt clean. Validated end-to-end with both real 2-profile setups and synthetic 3-profile same-email collision tests.

The plugin is one skill (chrome-multi-profile) with progressive-disclosure SKILL.md, a 720-line library file, two reference docs (profile-detection.md, patterns.md), one slash command (/chrome-debug), and a contributor lint script (shfmt + shellcheck + smoke test, auto-fetches tools via nix run if not in PATH).

MIT licensed. macOS only.
```

## Posting order suggestion

1. **Hacker News Show HN first** (Tuesday-Thursday 8-10am PT) — HN is the highest-signal audience for technical depth like the SNSS approach
2. **Reddit r/ClaudeCode** within 30 minutes of the HN post — same content, different audience, leverages any HN traffic spike
3. **Twitter/X thread** same day, link to either the HN post (if it's getting comments) or the GitHub repo
4. **Blog post on dev.to** the next day — gives the long-form readers something to chew on once initial discovery has happened
5. **Anthropic Console submission** any time — review is async and slow, doesn't depend on launch timing
6. **Cross-post Reddit r/ClaudeAI** 24 hours later for additional reach

## What this kit deliberately skips

- **Product Hunt** — overkill for a developer tool with no marketing site
- **Awesome lists** — `VoltAgent/awesome-openclaw-skills` requires the skill to be in the OpenClaw registry first (it's a separate ecosystem from Claude Code, see CONTRIBUTING.md which explicitly disqualifies external repos)
- **LinkedIn** — wrong audience for a CLI plugin
- **YouTube demo video** — would be useful but requires recording effort beyond the plain text launch

## After launch — track results

- GitHub stars over the first 48 hours
- Issues / PRs (real-world bug reports validate the approach)
- Specifically watch for **same-email collision reports** — that's the part of the design most worth real-world testing
