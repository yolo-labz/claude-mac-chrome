# Media provenance

Checked 21/09/2026 at base `917ba77`. OpenAI-authored documentation correction.

The old `assets/cmac-demo.svg` was a hand-authored illustration, not terminal
capture. The real dispatch table in `skills/chrome-multi-profile/chrome-lib.sh`
accepts `catalog`, `window_for <ref>` and `js <win> <tab> <code>`; it does not accept
the depicted `chrome-multi-profile "Work" --js ...` command. Catalog output is a
JSON object keyed by directory. The old 41/63 ms and percentile numbers had no
linked recording receipt. The replacement 1200×620 SVG contains no execution
output, account identifiers or timings and visibly labels itself an illustration.

## Isolated macOS capture (not yet executed)

Use a disposable macOS user/session with no daily Chrome windows. The library's
AppleScript enumerates Google Chrome windows, so merely opening a fresh tab in a
live user session does not isolate account data. No suitable isolated Mac was
established during this Linux-only slice; no SSH/hardware action was attempted.

1. Start Google Chrome with a new temporary `--user-data-dir`, no sign-in, and
   open a loopback HTML fixture titled `Local demo`.
2. Set `CHROME_USER_DATA_DIR` to that directory, `TMPDIR` to a dedicated cache
   directory, and `CHROME_ROLES_FILE` to a synthetic empty roles file. Enable
   JavaScript from Apple Events only for the disposable environment if required.
3. Execute `bash skills/chrome-multi-profile/chrome-lib.sh catalog`. The profile
   fixture can have display name `Demo` without an account email.
4. Obtain the fixture window/tab IDs from the actual AppleScript window dump;
   `register_window <id> Default` gives the fixture its explicit `cmc:` identity.
   Execute `window_for Default`, then `js <returned-window> <fixture-tab> 'document.title'`.
5. Record actual command output and local page. Save source revision, macOS/Chrome
   versions, cast/video, dimensions, duration and hashes. Assert the title is the
   fixture title. Do not infer event trust from a successful JavaScript dispatch.
6. Stop only that disposable environment. No sign-in or account data is needed.

Linux verification in this slice only parses the SVG and runs catalog against a
synthetic Local State fixture. It does not validate AppleScript or profile binding.
