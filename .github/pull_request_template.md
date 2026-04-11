## Summary

<!-- What does this PR change and why? 1-3 bullets. -->

## Type of change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation only
- [ ] Fixture contribution (new safety rail test case)
- [ ] Golden regeneration (re-run via `scripts/regenerate-goldens.sh`)
- [ ] Dependency vendoring refresh

## Safety impact

<!-- Does this change touch the safety gauntlet, URL blocklist, trigger
     lexicon, rate limiter, audit log, or any _chrome_safety_check_js
     rail? If YES, describe what and why. Per spec §NFR-V2-FX-7, any
     PR touching >3 fixture goldens or the safety JS will be auto-routed
     to a security reviewer via CODEOWNERS. -->

- Touches safety gauntlet: [ ] yes / [ ] no
- Touches trigger lexicon: [ ] yes / [ ] no
- Touches URL blocklist: [ ] yes / [ ] no
- Changes fixture goldens: [ ] yes / [ ] no (count: _N_)

## Fixture contribution protocol

*Skip this section if this PR does not add a fixture.*

- [ ] Fixture declares `target_rail` in header comment
- [ ] Fixture declares `isolation_proof` — prose explaining why exactly ONE rail fires
- [ ] Fixture declares `last_reviewed` date
- [ ] `.expected.json` is the exact envelope from a fresh happy-dom run (no hand-edits)
- [ ] Rail isolation meta-test passes (disabling the target rail makes envelope `ok:true`)
- [ ] Negative control run logged in the PR description

## Test plan

- [ ] `bash scripts/lint.sh` passes locally
- [ ] `tests/run.sh` passes (bats + js-fixtures)
- [ ] If Playwright-relevant: integration suite run attached

## Checklist

- [ ] Changes are minimal — no unrelated refactors
- [ ] Existing behavior preserved — no silent side effects
- [ ] Updated docs if behavior changed (api.md, README, CHANGELOG)
- [ ] Updated `HAPPY-DOM-FIDELITY.md` if new DOM API introduced in safety JS
- [ ] No new runtime dependencies added
- [ ] No unsafe DOM injection sinks on untrusted input
