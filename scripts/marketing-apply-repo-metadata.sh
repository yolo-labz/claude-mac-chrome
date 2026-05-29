#!/usr/bin/env bash
# scripts/marketing-apply-repo-metadata.sh
#
# Idempotently sets the marketing surface on the GitHub repo:
#   - Description (<=120 chars, capability-only framing)
#   - Topics (3-10, GitHub topic-discovery surface)
#
# Run from an authenticated `gh` shell (gh auth login first). Safe to re-run;
# `gh api` PATCH/PUT are idempotent on identical payloads. Source of truth for
# the marketing copy is README.md `## Capability` and `## How claude-mac-chrome
# compares`.
#
# Provenance: shipped with PR #66 (feat(marketing): hero + capability +
# comparison + demo + OG) per spec 024-yolo-labz-portfolio-consolidation-2026Q2
# Phase 6/7 sibling rollout following the wa#172 class-leader pattern.

set -euo pipefail

REPO="${REPO:-yolo-labz/claude-mac-chrome}"

DESCRIPTION="Chrome multi-profile automation for Claude Code on macOS. Local State catalog + AppleScript IDs."

# 8 topics, GitHub topic-discovery surface. Order does not matter; GitHub stores
# them lowercase + sorted on retrieval.
TOPICS_JSON='{"names":["chrome","macos","applescript","multi-profile","claude-code","bash","slsa","automation"]}'

echo "-> patching description on ${REPO}"
gh api -X PATCH "repos/${REPO}" -f description="${DESCRIPTION}" --jq '.description'

echo "-> putting topics on ${REPO}"
printf '%s' "${TOPICS_JSON}" | gh api -X PUT "repos/${REPO}/topics" --input - --jq '.names | join(", ")'

echo "ok done"
