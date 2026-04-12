# Contributing to claude-mac-chrome

Thank you for considering a contribution. This document covers the development
workflow, conventions, and compatibility requirements.

## Prerequisites

- macOS (the plugin is macOS-only by design)
- Bash 3.2+ (macOS system bash) for runtime compatibility
- Modern bash (5.x via Homebrew) for the test suite
- [bats-core](https://github.com/bats-core/bats-core) for shell unit tests
- [shellcheck](https://github.com/koalaman/shellcheck) and [shfmt](https://github.com/mvdan/sh)
- [jq](https://github.com/jqlang/jq)
- [pre-commit](https://pre-commit.com/) (recommended)

Install test dependencies on macOS:

```bash
brew install bash bats-core shellcheck shfmt jq
```

## Development loop

```bash
# Full verification: shfmt + shellcheck + happy-dom fidelity lint +
# fixture determinism lint + bats + js-fixtures + mutation + smoke
bash scripts/lint.sh

# Fast subset (bats shell tests only)
bats tests/bats/*.bats

# Integration tests (Playwright, requires npm ci in tests/integration first)
cd tests/integration && npx playwright test
```

## Pre-commit hooks

Install the hooks once:

```bash
pre-commit install
```

This runs `zizmor` (GitHub Actions workflow linting), `actionlint` (Actions
syntax checking), `shellcheck`, and `shfmt` on every commit.

## Bash 3.2 compatibility

All shell code must run on macOS's system bash (3.2.57). This is a hard
requirement enforced by `scripts/lint.sh`. Specifically, do NOT use:

- `declare -A` (associative arrays)
- `mapfile` / `readarray`
- `${var^^}` / `${var,,}` (case modification)
- `|&` (pipe stderr)
- `<(...)` process substitution in contexts where bash 3.2 chokes
- `[[ $var =~ regex ]]` with stored regex variables (behaves differently)

Use `tr '[:lower:]' '[:upper:]'` for case conversion, plain arrays with index
lookups for key-value pairs, and POSIX-compatible constructs wherever possible.

## Commit conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code restructuring without behavior change
- `chore:` — maintenance, CI, dependencies
- `docs:` — documentation only
- `test:` — test additions or changes

Keep the subject line under 72 characters. Use the body for details.

## Pull request workflow

1. Create a feature branch from `main`: `git checkout -b NNN-short-description`
2. Make your changes and commit with conventional commits
3. Rebase on latest main: `git fetch origin main && git rebase origin/main`
4. Push: `git push -u origin HEAD`
5. Open a PR with a descriptive title and body
6. Wait for CI checks to pass (lint, test, integration, CodeQL, OSV-Scanner)
7. Address review feedback
8. Maintainer merges via squash merge

Never push directly to `main`. Never re-tag a release.

## Fixture golden files

If your change affects fixture output (`.expected.json` files in `tests/fixtures/`):

1. Commit your source changes first
2. Run `scripts/regenerate-goldens.sh` in a **separate** commit
3. This separation lets reviewers audit envelope diffs in isolation

PRs touching more than 3 fixture goldens require security review (routed
automatically via CODEOWNERS).

## Code of conduct

Be respectful. File issues at
https://github.com/yolo-labz/claude-mac-chrome/issues for bugs and feature
requests. Security issues go through the private vulnerability reporting flow
described in [SECURITY.md](SECURITY.md).
