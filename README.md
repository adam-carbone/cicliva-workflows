# Domiva Workflows

Shared GitHub Actions reusable workflows for all Domiva product repos.

Every Domiva repo uses a thin caller pattern: local `.github/workflows/` files are just wrappers that delegate to these shared workflows via `uses: Domiva-Life/domiva-workflows/.github/workflows/<name>.yml@main`.

---

## The Agent Pipeline

```
You write a GitHub Issue with @claude
           ↓
Claude Coding Agent reads the issue → writes code → opens a PR
           ↓
Build + Test runs (repo-specific CI)
           ↓
    ┌── fails ──────────────────────────────────────────┐
    │                                                   │
    │          PR Fix Agent reads CI logs               │
    │          pushes fixes → Build + Test reruns       │
    │          (max 3 attempts, then escalates to you)  │
    │                                                   │
    └── passes ─────────────────────────────────────────┘
           ↓
    PR Review runs → reads the diff → categorizes findings
           ↓
    ┌── CHANGES_REQUESTED (blocking issues found) ──────┐
    │                                                   │
    │   Merge button is blocked                         │
    │   PR Fix Agent reads blocking findings            │
    │   pushes fixes → dismisses blocking review        │
    │   Build + Test reruns → PR Review reruns          │
    │   (max 3 attempts, then escalates to you)         │
    │                                                   │
    └── APPROVED (no blocking issues) ──────────────────┘
           ↓
    You see a green ✓ approval in the PR
    Read the diff + review comment, then merge
           ↓
    Issue Orchestrator fires → triggers next issue in queue
           ↓
    Repeat
```

---

## Shared Workflows

### `pr-review.yml`

Reviews a PR after CI passes. Posts a structured comment classifying findings as **BLOCKING** or **NIT**, then submits a formal GitHub review (`CHANGES_REQUESTED` or `APPROVED`).

| Input | Type | Required | Description |
|---|---|---|---|
| `pr_number` | number | yes | PR number to review |
| `repo` | string | yes | `owner/repo` (e.g. `Domiva-Life/domiva-cloud`) |

| Secret | Required | Description |
|---|---|---|
| `anthropic_api_key` | yes | Anthropic API key for Claude |

**Finding categories:**

- **BLOCKING** — automatically fixed by the PR Fix Agent. Only used for: incorrect behavior (doesn't match the issue spec), logic flaws or bugs, security vulnerabilities, missing test coverage for behavior changes, hard violations of CLAUDE.md conventions.
- **NIT** — informational only, never auto-fixed. Used for: style preferences, optional refactors, nice-to-have improvements.

---

### `pr-fix.yml`

Reads CI failure logs or BLOCKING review findings and pushes fixes. Tracks fix attempts via hidden markers in PR comments — escalates to a human after 3 failed attempts.

| Input | Type | Required | Description |
|---|---|---|---|
| `pr_number` | number | yes | PR number to fix |
| `head_branch` | string | yes | Branch name of the PR head |
| `triggered_by` | string | yes | `Build + Test` or `PR Review` |
| `run_id` | string | yes | GitHub Actions run ID (for fetching CI logs) |
| `repo` | string | yes | `owner/repo` |
| `stack` | string | yes | `java` or `flutter` — controls which setup steps run |
| `build_command` | string | yes | Build command to run after fixes (e.g. `gradle build`) |
| `test_command` | string | yes | Test command to run after fixes (e.g. `gradle test`) |

| Secret | Required | Description |
|---|---|---|
| `anthropic_api_key` | yes | Anthropic API key for Claude |

**Escalation behavior:** After 3 fix attempts without resolving all blocking issues, the agent stops and posts a human-escalation comment on the PR.

---

### `issue-chain.yml`

When a PR merges to main, reads `Next: #N` from the closed issue body and posts `@claude` on the next issue in the queue. Enables sequential issue chains where each issue is tackled automatically after the previous one merges.

| Secret | Required | Description |
|---|---|---|
| `github_token` | yes | `${{ secrets.GITHUB_TOKEN }}` |

**Issue format for chaining:**
```
**Depends on:** #N
**Next:** #N+1

@claude   ← only on the first issue in the chain
```

---

## Adding to a New Repo

1. Create `.github/workflows/claude.yml` — the coding agent (repo-specific, see any Domiva repo for the template)
2. Create `.github/workflows/ci.yml` — your build and test CI (repo-specific, must be named `Build + Test`)
3. Create `.github/workflows/pr-review.yml` — thin caller:

```yaml
name: PR Review

on:
  workflow_run:
    workflows: ["Build + Test"]
    types: [completed]
  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to review'
        required: true

jobs:
  review:
    if: |
      github.event_name == 'workflow_dispatch' ||
      (
        github.event.workflow_run.pull_requests[0] != null &&
        github.event.workflow_run.conclusion == 'success'
      )
    uses: Domiva-Life/domiva-workflows/.github/workflows/pr-review.yml@main
    with:
      pr_number: ${{ github.event.workflow_run.pull_requests[0].number || inputs.pr_number }}
      repo: ${{ github.repository }}
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

4. Create `.github/workflows/ci-auto-fix.yml` — thin caller (Java example):

```yaml
name: PR Fix Agent

on:
  workflow_run:
    workflows: ["Build + Test", "PR Review"]
    types: [completed]

permissions:
  contents: write
  pull-requests: write
  actions: read
  issues: write
  id-token: write

jobs:
  fix:
    if: |
      github.event.workflow_run.pull_requests[0] != null &&
      !startsWith(github.event.workflow_run.head_branch, 'claude-fix-') &&
      (
        (github.event.workflow_run.name == 'Build + Test' && github.event.workflow_run.conclusion == 'failure') ||
        (github.event.workflow_run.name == 'PR Review' && github.event.workflow_run.conclusion == 'success')
      )
    uses: Domiva-Life/domiva-workflows/.github/workflows/pr-fix.yml@main
    with:
      pr_number: ${{ github.event.workflow_run.pull_requests[0].number }}
      head_branch: ${{ github.event.workflow_run.head_branch }}
      triggered_by: ${{ github.event.workflow_run.name }}
      run_id: ${{ github.event.workflow_run.id }}
      repo: ${{ github.repository }}
      stack: java
      build_command: gradle build
      test_command: gradle test
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

For Flutter, use `stack: flutter`, `build_command: flutter build apk --debug`, `test_command: flutter test`.

5. Create `.github/workflows/issue-chain.yml` — thin caller:

```yaml
name: Issue Orchestrator

on:
  pull_request:
    types: [closed]
    branches: [main]

jobs:
  chain:
    if: github.event.pull_request.merged == true
    uses: Domiva-Life/domiva-workflows/.github/workflows/issue-chain.yml@main
    secrets:
      github_token: ${{ secrets.GITHUB_TOKEN }}
```

6. Set `ANTHROPIC_API_KEY` in the repo's **Settings → Secrets and variables → Actions**.

---

## Supported Stacks

| Stack | `stack` input | Setup |
|---|---|---|
| Java / Spring Boot | `java` | Java 21 (Temurin) + Gradle 8.7 |
| Flutter | `flutter` | Flutter via FVM + `flutter pub get` |

## Adding a New Stack

Add a new conditional block in `pr-fix.yml` under the setup steps section:

```yaml
- name: Set up <stack>
  if: inputs.stack == '<stack>'
  run: |
    # your setup commands
```

Then use the new `stack` value in your repo's `ci-auto-fix.yml`.
