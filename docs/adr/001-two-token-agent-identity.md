# 001. Two-Token Agent Identity Strategy

**Status**: Accepted
**Date**: 2026-03-12

## Context

The Domiva agent workflow involves three actors:

1. **Claude (Coding Agent)** — opens PRs, commits code
2. **Claude (PR Review Agent)** — reviews PRs and posts CHANGES_REQUESTED
3. **Human (adam-carbone)** — approves and merges

GitHub branch protection requires at least 1 approving review before merge. This creates a conflict:
if the same identity opens the PR AND reviews it, GitHub considers it self-review and the human
may be blocked from approving (or the approval itself may be invalid depending on protection settings).

## Decision

All agent workflows use **two separate tokens with distinct roles**:

| Token | Source | Role |
|-------|--------|------|
| **Bot app token** | `DOMIVA_AGENT_APP_ID` + `DOMIVA_AGENT_PRIVATE_KEY` via `actions/create-github-app-token@v1` | Checkout, git operations, opening PRs, `github_token` in `claude-code-action` (PR authorship) |
| **`github.token`** | GitHub Actions default | Posting issue/PR comments that don't constitute a formal review |

The bot app token generates a token for the `domiva-life-agent` GitHub App installation. PRs opened
with this token appear as authored by `domiva-life-agent[bot]`, not `adam-carbone`. This means:

- The PR Review agent posts CHANGES_REQUESTED reviews **as the bot**, not as Adam
- Adam (adam-carbone) is not the PR author, so GitHub allows him to submit an approving review
- Adam is not the reviewer, so the separation is clean: bot reviews → human approves → human merges

The token is generated with `owner: Domiva-Life` so it is org-scoped and can access all repos
the app is installed on — this is required so agents running in product repos (domiva-cloud, domiva-mobile)
can read shared resources like `Domiva-Life/domiva-workflows/CLAUDE-shared.md`.

## What breaks if you change this

- **If you switch checkout to `github.token`**: The PR is authored by `github-actions[bot]` or adam-carbone
  (depending on context). Adam may be blocked from approving his own PRs under strict protection rules.
- **If you remove `owner: Domiva-Life`**: The bot token is scoped to the calling repo only.
  Agents will get HTTP 404 when trying to read `domiva-workflows/CLAUDE-shared.md`.
- **If you use `github.token` for the Claude `github_token` param**: Reviews are submitted as
  `github-actions[bot]` (not the Domiva app bot), breaking `allowed_bots` filtering in Fix Agent
  and potentially allowing self-review if the token maps to Adam's identity.

## Consequences

- All product repos must have `DOMIVA_AGENT_APP_ID` and `DOMIVA_AGENT_PRIVATE_KEY` secrets (set at org level)
- The GitHub App (`domiva-life-agent`) must be installed on all repos it needs to access, including `domiva-workflows`
- The app needs `contents: write`, `pull-requests: write`, `issues: write` permissions on product repos
