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
    "ready to merge" label added to PR
    You see a green ✓ approval + the label, then merge
           ↓
    Issue Orchestrator fires → triggers next issue in queue
           ↓
    Repeat
```

---

## Prerequisites

### Anthropic API Key
Set `ANTHROPIC_API_KEY` as an org-level secret in **github.com/orgs/Domiva-Life/settings/secrets/actions**. All repos inherit it automatically.

### Domiva Agent GitHub App (required for full automation)

The coding agent pushes code using `GITHUB_TOKEN` by default. GitHub suppresses `workflow_run` events from `GITHUB_TOKEN` pushes to prevent infinite loops — which means PR Review and the Fix Agent CI failure path won't auto-trigger without a dedicated app identity.

**One-time setup:**

1. Go to **github.com/organizations/Domiva-Life/settings/apps** → New GitHub App
2. Configure:
   - Name: `Domiva Agent`
   - Homepage URL: `https://github.com/Domiva-Life`
   - Webhook: **disabled**
   - Repository permissions: Contents (R/W), Pull requests (R/W), Issues (R/W), Actions (R), Metadata (R)
   - Where installed: **Only on this account**
3. Click **Create GitHub App** — note the **App ID**
4. Scroll down → **Generate a private key** (downloads a `.pem` file)
5. Left sidebar → **Install App** → install on `Domiva-Life` → All repositories
6. Add two org secrets:
   ```bash
   gh secret set DOMIVA_AGENT_APP_ID --org Domiva-Life --body "<App ID>"
   gh secret set DOMIVA_AGENT_PRIVATE_KEY --org Domiva-Life < domiva-agent.private-key.pem
   ```

Once set, add a token-generation step to each repo's `claude.yml` and `ci-auto-fix.yml` (see workflow templates below).

---

## Shared Workflows

### `pr-review.yml`

Reviews a PR after CI passes. Posts a structured comment classifying findings as **BLOCKING** or **NIT**, then submits a formal GitHub review (`CHANGES_REQUESTED` or `APPROVED`). Adds a `ready to merge` label on approval, removes it on changes requested.

| Input | Type | Required | Description |
|---|---|---|---|
| `pr_number` | number | yes | PR number to review |
| `repo` | string | yes | `owner/repo` (e.g. `Domiva-Life/domiva-cloud`) |

| Secret | Required | Description |
|---|---|---|
| `anthropic_api_key` | yes | Anthropic API key for Claude |

**Finding categories:**

- **BLOCKING** — automatically fixed by the PR Fix Agent. Only used for: incorrect behavior, logic flaws or bugs, security vulnerabilities, missing test coverage for behavior changes, hard violations of CLAUDE.md conventions.
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
| `build_command` | string | yes | Build command to run after fixes |
| `test_command` | string | yes | Test command to run after fixes |

| Secret | Required | Description |
|---|---|---|
| `anthropic_api_key` | yes | Anthropic API key for Claude |

**Escalation:** After 3 fix attempts, the agent stops and posts a human-escalation comment on the PR.

---

### `issue-chain.yml`

When a PR merges to main, reads `Next: #N` from the closed issue body and posts `@claude` on the next issue in the queue.

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

## PR Commands

Post these as comments on any open PR in any repo using this pipeline:

| Command | What it does |
|---|---|
| `/re-review` | Triggers a fresh PR Review run — use after pushing fixes manually or when `CHANGES_REQUESTED` needs re-evaluation |
| `/fix 2` | Asks the Fix Agent to address nit 2 from the review comment |
| `/fix all` | Addresses every nit from the most recent review comment in one run |
| `/fix 1, 3-5` | Addresses multiple nits in one Fix Agent run |
| `/fix 2  your feedback` | Fix nit 2 with inline guidance — agent treats it as highest-priority input |
| `/fix 2  Token security`<br>`Detailed guidance body` | Fix nit 2 with a topic + guidance — inline text becomes the **topic**, subsequent lines become the **guidance** |
| `/extend` | Grants 1 more Fix Agent attempt (default limit is 5) |
| `/extend 3` | Grants 3 more Fix Agent attempts |
| `@claude <instruction>` | Direct instruction to the Coding Agent — works on **issues** (agent implements and opens a PR) and **PRs** (agent reads the thread and pushes a follow-up commit) |

**Feedback syntax for `/fix`:**

```
/fix 2
```
Standard — no feedback, agent uses its own judgment.

```
/fix 2  Use SecureRandom not UUID — UUIDs are not cryptographically random
```
Inline guidance only (no body follows) — entire inline text is treated as guidance.

```
/fix 2  Token security
Use SecureRandom not UUID.randomUUID — not crypto random.
Both shareToken and inviteeToken need this fix.
```
Topic + guidance — inline text (after two or more spaces) becomes the **topic**, subsequent lines become the **guidance**. The PR comment shows: **Topic:** Token security / **Guidance:** Use SecureRandom...

```
/fix 2
Use SecureRandom not UUID.randomUUID — not crypto random.
Both shareToken and inviteeToken need this fix.
```
Guidance body only (no inline text) — all lines treated as guidance.

---

## Cicliva Platform

This repo doubles as the source for the Cicliva agent platform — a productized version of the Domiva agent pipeline for external customers.

### Repository Roles

| Repo | Purpose |
|---|---|
| `Domiva-Life/domiva-workflows` | Development — all changes made here |
| `cicliva/cicliva-workflows` | Distribution — fork synced automatically on every push to main; customers mirror from here |

### Publish Pipeline

```
commit to Domiva-Life/domiva-workflows (main)
  → sync-to-cicliva.yml syncs the fork via merge-upstream
    → publish-scripts.yml triggers on cicliva/cicliva-workflows
      → scripts land in gs://cicliva-public-scripts/
        → available to all customers immediately
```

> **Note:** `sync-to-cicliva.yml` currently triggers on every push to main. TODO: tighten to PR merges only before onboarding real customers.

### Customer-Facing Scripts

| Script | Purpose |
|---|---|
| `scripts/cicliva-setup.sh` | Beta customer setup — validates token, mirrors `cicliva-workflows` into their org, runs install |
| `scripts/agent-workflows.sh` | All customers — copies workflow files, sets secrets, wires learnings |

Scripts publish automatically when changed. To publish manually during development:
```bash
gcloud storage cp scripts/cicliva-setup.sh gs://cicliva-public-scripts/cicliva-setup.sh
gcloud storage cp scripts/agent-workflows.sh gs://cicliva-public-scripts/agent-workflows.sh
```

### Learnings Pipeline

Agent runs write learnings to `/tmp/cicliva-learnings.jsonl`. A post-step in the agent workflow POSTs records to the Cicliva learnings API (`/ingest`), which stores them in `gs://cicliva-learnings/` as daily JSONL files.

Synthesis pipeline (planned): raw records → per-customer distillation → cross-customer synthesis → `agent-learnings/*.md` updated → agents get smarter on next run.

See `domiva-product/infrastructure/cicliva-learnings-system.md` for full design.

### Secrets

| Secret | Repo | Purpose |
|---|---|---|
| `CICLIVA_SYNC_TOKEN` | `Domiva-Life/domiva-workflows` | Classic PAT (`repo` + `workflow` scope) — triggers fork sync |
| `CICLIVA_WIF_PROVIDER` | `cicliva/cicliva-workflows` | Workload Identity Federation provider for GCS publish |
| `CICLIVA_WIF_SA` | `cicliva/cicliva-workflows` | WIF service account for GCS publish |
| `CICLIVA_SCRIPTS_BUCKET` | `cicliva/cicliva-workflows` | GCS bucket name (`cicliva-public-scripts`) |

---

## Adding to a New Repo

Run the install script from the root of your repo:

```bash
bash <(curl -fsSL -H "Authorization: token $(gh auth token)" https://raw.githubusercontent.com/Domiva-Life/domiva-workflows/main/scripts/agent-workflows.sh)
```

The script will:
1. Detect your stack (Flutter, Java, React Native) or prompt you to select one
2. Copy the correct workflow files into `.github/workflows/`
3. Prompt for required secrets and configure them via `gh secret set`

After install, verify everything is in place:

```bash
bash <(curl -fsSL -H "Authorization: token $(gh auth token)" https://raw.githubusercontent.com/Domiva-Life/domiva-workflows/main/scripts/agent-workflows.sh) doctor
```

`doctor` checks that all required workflow files exist, that each file matches the expected structure (correct triggers, jobs, and references), and that all required secrets are configured. Run it any time you suspect drift — after a manual edit, a merge, or when something in the pipeline stops behaving as expected.

To interactively fix any issues doctor finds:

```bash
bash <(curl -fsSL -H "Authorization: token $(gh auth token)" https://raw.githubusercontent.com/Domiva-Life/domiva-workflows/main/scripts/agent-workflows.sh) doctor --cure
```

`doctor --cure` walks through each failing check, shows you the diff, and prompts before applying each fix.

The one file you still need to create manually is `.github/workflows/ci.yml` — your repo-specific build and test CI. The job must be named `build` and the workflow named `Build + Test` for the agent pipeline to wire up correctly.

---

## Manual Workflow Reference

The install script handles everything below automatically. This section is reference documentation for what gets installed.

### `.github/workflows/ci.yml` — Build and Test CI

### `.github/workflows/claude.yml` — Coding Agent

```yaml
name: Claude Coding Agent

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - name: Generate bot token
        id: bot-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.DOMIVA_AGENT_APP_ID }}
          private-key: ${{ secrets.DOMIVA_AGENT_PRIVATE_KEY }}

      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          token: ${{ steps.bot-token.outputs.token }}
          fetch-depth: 1

      # Add stack-specific setup here (Java, Flutter, etc.)

      - name: Check Anthropic API credit
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          RESPONSE=$(curl -s --max-time 10 -X POST https://api.anthropic.com/v1/messages \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -H "content-type: application/json" \
            -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}')
          if echo "$RESPONSE" | grep -q '"type":"error"'; then
            if echo "$RESPONSE" | grep -qi "credit\|billing\|balance"; then
              echo "::error::Anthropic API billing issue — credit balance too low. Top up at https://console.anthropic.com and retry."
              exit 1
            fi
          fi
          echo "Anthropic API key OK"

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ steps.bot-token.outputs.token }}
          claude_args: --max-turns 50 --allowedTools "Bash(gh pr create:*),Bash(gh pr view:*),Bash(git add:*),Bash(git commit:*),Bash(git push:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git rm:*),Edit,MultiEdit,Write,Read,Glob,Grep,LS"
```

### `.github/workflows/pr-review.yml` — PR Review

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

### `.github/workflows/ci-auto-fix.yml` — PR Fix Agent (Java example)

```yaml
name: PR Fix Agent

on:
  workflow_run:
    workflows: ["Build + Test"]
    types: [completed]
  pull_request_review:
    types: [submitted]

permissions:
  contents: write
  pull-requests: write
  actions: read
  issues: write
  id-token: write

jobs:
  fix:
    if: |
      (
        github.event_name == 'workflow_run' &&
        github.event.workflow_run.pull_requests[0] != null &&
        !startsWith(github.event.workflow_run.head_branch, 'claude-fix-') &&
        github.event.workflow_run.name == 'Build + Test' &&
        github.event.workflow_run.conclusion == 'failure'
      ) ||
      (
        github.event_name == 'pull_request_review' &&
        github.event.review.state == 'changes_requested' &&
        !startsWith(github.event.pull_request.head.ref, 'claude-fix-')
      )
    uses: Domiva-Life/domiva-workflows/.github/workflows/pr-fix.yml@main
    with:
      pr_number: ${{ github.event_name == 'pull_request_review' && github.event.pull_request.number || github.event.workflow_run.pull_requests[0].number }}
      head_branch: ${{ github.event_name == 'pull_request_review' && github.event.pull_request.head.ref || github.event.workflow_run.head_branch }}
      triggered_by: ${{ github.event_name == 'pull_request_review' && 'PR Review' || github.event.workflow_run.name }}
      run_id: ${{ github.event.workflow_run.id || 0 }}
      repo: ${{ github.repository }}
      stack: java
      build_command: gradle build
      test_command: gradle test
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

For Flutter: `stack: flutter`, `build_command: flutter pub get && dart run build_runner build --delete-conflicting-outputs`, `test_command: flutter test`.

### `.github/workflows/issue-chain.yml` — Issue Orchestrator

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
