#!/usr/bin/env bash
# agent-workflows.sh — install and maintain agent workflow files in a repo
#
# Usage:
#   agent-workflows.sh [install] [--stack STACK] [--repo OWNER/NAME] [--workflow-repo OWNER/NAME]
#   agent-workflows.sh doctor [--cure] [--repo OWNER/NAME]
#   agent-workflows.sh -h | --help
#
# Commands:
#   install (default)   Copy agent workflow files into .github/workflows/ and set up secrets
#   doctor              Check for drift, missing files, or missing secrets
#   doctor --cure       Same, but interactively apply fixes
#
# Options:
#   --stack STACK            Stack type: flutter | java | react-native
#   --repo OWNER/NAME        Target repo (defaults to current directory's remote)
#   --workflow-repo OWNER/NAME  Workflow library repo (defaults to Domiva-Life/domiva-workflows)
#   --cure                   (doctor only) Prompt to apply each fix found
#   -h, --help               Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
AGENT_WORKFLOWS_CONF=".github/.agent-workflows"
DEFAULT_WORKFLOW_REPO="Domiva-Life/domiva-workflows"

SUPPORTED_STACKS="flutter java react-native"

build_command_for() {
  case "$1" in
    flutter)      echo "flutter pub get && dart run build_runner build --delete-conflicting-outputs" ;;
    java)         echo "gradle build" ;;
    react-native) echo "npm install" ;;
    *)            die "Unknown stack: $1. Supported: $SUPPORTED_STACKS" ;;
  esac
}

test_command_for() {
  case "$1" in
    flutter)      echo "flutter test" ;;
    java)         echo "gradle test" ;;
    react-native) echo "npx jest" ;;
    *)            die "Unknown stack: $1. Supported: $SUPPORTED_STACKS" ;;
  esac
}

REQUIRED_SECRETS=(
  ANTHROPIC_API_KEY
  AGENT_APP_ID
  AGENT_PRIVATE_KEY
  REVIEWER_APP_ID
  REVIEWER_PRIVATE_KEY
)

WORKFLOW_FILES=(claude.yml review.yml ci-auto-fix.yml)
DOCTOR_CHECKS=()  # built dynamically in cmd_doctor based on configured workflow repo

# ─── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
agent-workflows.sh — install and maintain Domiva agent workflow files in a repo

Usage:
  agent-workflows.sh [install] [--stack STACK] [--repo OWNER/NAME]
  agent-workflows.sh doctor [--cure] [--repo OWNER/NAME]
  agent-workflows.sh -h | --help

Commands:
  install (default)   Copy agent workflow files into .github/workflows/ and set up secrets
  doctor              Check for drift, missing files, or missing secrets
  doctor --cure       Same, but interactively apply fixes

Options:
  --stack STACK       Stack type: flutter | java | react-native
  --repo OWNER/NAME   Target repo (defaults to current directory's remote)
  --cure              (doctor only) Prompt to apply each fix found
  --skip-secrets      (doctor only) Skip secret configuration checks (useful in CI)
  -h, --help          Show this help

Examples:
  agent-workflows.sh                           # install with prompts
  agent-workflows.sh install --stack flutter
  agent-workflows.sh doctor
  agent-workflows.sh doctor --cure
  agent-workflows.sh doctor --repo Domiva-Life/domiva-mobile
EOF
  exit 0
}

die() { echo "error: $*" >&2; exit 1; }

ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
fail() { echo "  ✗ $*"; }

detect_repo() {
  gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null \
    || die "Could not detect repo. Run from inside a git repo or pass --repo OWNER/NAME."
}

detect_stack() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
  if [[ -f "$repo_root/pubspec.yaml" ]]; then
    echo "flutter"
  elif [[ -f "$repo_root/build.gradle" || -f "$repo_root/build.gradle.kts" || -d "$repo_root/gradlew" ]]; then
    echo "java"
  elif [[ -f "$repo_root/package.json" ]]; then
    echo "react-native"
  else
    echo ""
  fi
}

prompt_stack() {
  local detected="$1"
  local stacks=("flutter" "java" "react-native")

  if [[ -n "$detected" ]]; then
    read -r -p "Detected stack: $detected. Use it? [Y/n] " confirm
    if [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]]; then
      echo "$detected"
      return
    fi
  fi

  echo "Select stack:"
  # shellcheck disable=SC2206
  local stacks=($SUPPORTED_STACKS)
  select stack in "${stacks[@]}"; do
    [[ -n "$stack" ]] && { echo "$stack"; return; }
    echo "Invalid selection. Try again."
  done
}

apply_template() {
  local template_file="$1"
  local stack="$2"
  local workflow_repo="${3:-$DEFAULT_WORKFLOW_REPO}"
  local build_cmd test_cmd
  build_cmd="$(build_command_for "$stack")"
  test_cmd="$(test_command_for "$stack")"

  sed \
    -e "s|{{STACK}}|$stack|g" \
    -e "s|{{BUILD_COMMAND}}|$build_cmd|g" \
    -e "s|{{TEST_COMMAND}}|$test_cmd|g" \
    -e "s|{{WORKFLOW_REPO}}|$workflow_repo|g" \
    -e "s|{{REPO_INSTRUCTIONS}}|Follow the project conventions and any CLAUDE.md instructions.|g" \
    "$template_file"
}

# Which secrets take a file path (PEM) vs a plain value
secret_is_file() {
  case "$1" in
    *_PRIVATE_KEY) return 0 ;;
    *)             return 1 ;;
  esac
}

setup_secrets() {
  local repo="$1"
  local org
  org="$(echo "$repo" | cut -d'/' -f1)"

  echo ""
  read -r -p "Set up secrets now? [Y/n] " confirm
  [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]] || { echo "Skipping secrets — set them manually in GitHub repo settings."; return; }

  # Check what's already configured so we can skip
  local repo_secrets org_secrets all_secrets
  repo_secrets="$(gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || echo "")"
  org_secrets="$(gh secret list --org "$org" --json name --jq '.[].name' 2>/dev/null || echo "")"
  all_secrets="$(printf '%s\n%s' "$repo_secrets" "$org_secrets")"

  echo ""
  for secret in "${REQUIRED_SECRETS[@]}"; do
    if echo "$all_secrets" | grep -qx "$secret"; then
      echo "  $secret — already configured, skipping"
      continue
    fi

    if secret_is_file "$secret"; then
      # PEM file — prompt for path
      while true; do
        read -r -p "  $secret — path to PEM file: " filepath
        filepath="${filepath/#\~/$HOME}"  # expand ~ manually (read doesn't do it)
        if [[ -f "$filepath" ]]; then
          gh secret set "$secret" --repo "$repo" < "$filepath"
          echo "  $secret set."
          break
        else
          echo "  File not found: $filepath"
        fi
      done
    else
      # Plain value — masked input
      local value=""
      while [[ -z "$value" ]]; do
        read -r -s -p "  $secret: " value
        echo ""
        [[ -z "$value" ]] && echo "  Value cannot be empty."
      done
      gh secret set "$secret" --repo "$repo" --body "$value"
      echo "  $secret set."
    fi
  done
}

show_diff_and_prompt() {
  local dest="$1"
  local new_content="$2"
  local label="$3"

  if [[ ! -f "$dest" ]]; then
    echo "  New file: $dest"
  else
    diff <(cat "$dest") <(echo "$new_content") || true
  fi

  read -r -p "  Apply fix for $label? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$new_content" > "$dest"
    echo "  Applied."
    return 0
  else
    echo "  Skipped."
    return 1
  fi
}

# ─── install ──────────────────────────────────────────────────────────────────

cmd_install() {
  local stack="" repo="" workflow_repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stack)         stack="$2";         shift 2 ;;
      --repo)          repo="$2";          shift 2 ;;
      --workflow-repo) workflow_repo="$2"; shift 2 ;;
      *)               die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$repo" ]] && repo="$(detect_repo)"

  if [[ -z "$stack" ]]; then
    local detected
    detected="$(detect_stack)"
    stack="$(prompt_stack "$detected")"
  fi

  build_command_for "$stack" > /dev/null  # validates stack

  # Resolve workflow repo — use provided value, then saved config, then default
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
  local conf_file="$repo_root/$AGENT_WORKFLOWS_CONF"

  if [[ -z "$workflow_repo" && -f "$conf_file" ]]; then
    workflow_repo="$(grep '^WORKFLOW_REPO=' "$conf_file" | cut -d'=' -f2)"
  fi
  [[ -z "$workflow_repo" ]] && workflow_repo="$DEFAULT_WORKFLOW_REPO"

  local workflows_dir="$repo_root/.github/workflows"
  mkdir -p "$workflows_dir"

  echo ""
  echo "Installing agent workflows for stack '$stack' into $workflows_dir"
  echo ""

  for file in "${WORKFLOW_FILES[@]}"; do
    local dest="$workflows_dir/$file"
    local template="$TEMPLATES_DIR/$file"

    [[ -f "$template" ]] || die "Template not found: $template"

    if [[ -f "$dest" ]]; then
      echo "  Skipping $file (already exists — run 'doctor --cure' to update)"
    else
      apply_template "$template" "$stack" "$workflow_repo" > "$dest"
      echo "  Created $file"
    fi
  done

  # Save workflow repo to config for doctor to use
  echo "WORKFLOW_REPO=$workflow_repo" > "$conf_file"

  setup_secrets "$repo"

  echo ""
  echo "Done. Next steps:"
  echo "  1. Register a GitHub App for the agent and reviewer"
  echo "  2. Open a PR and post '@claude' on an issue to test the loop"
  echo ""
  echo "Run 'agent-workflows.sh doctor' at any time to check health."
}

# ─── doctor ───────────────────────────────────────────────────────────────────

cmd_doctor() {
  local cure=false skip_secrets=false repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cure)         cure=true; shift ;;
      --skip-secrets) skip_secrets=true; shift ;;
      --repo)         repo="$2"; shift 2 ;;
      *)              die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$repo" ]] && repo="$(detect_repo)"

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
  local workflows_dir="$repo_root/.github/workflows"

  # Read workflow repo from config if present
  local conf_file="$repo_root/$AGENT_WORKFLOWS_CONF"
  local workflow_repo="$DEFAULT_WORKFLOW_REPO"
  if [[ -f "$conf_file" ]]; then
    local saved
    saved="$(grep '^WORKFLOW_REPO=' "$conf_file" | cut -d'=' -f2)"
    [[ -n "$saved" ]] && workflow_repo="$saved"
  fi

  # Build doctor checks using the configured workflow repo
  DOCTOR_CHECKS=(
    "review.yml|uses: ${workflow_repo}/.github/workflows/pr-review.yml@main|calls pr-review.yml@main"
    "review.yml|dispatch-fix:|dispatch-fix job present"
    "review.yml|workflow_dispatch|workflow_dispatch trigger present"
    "review.yml|domiva-agent-lab#5|workflow_run disabled with issue reference"
    "ci-auto-fix.yml|uses: ${workflow_repo}/.github/workflows/pr-fix.yml@main|calls pr-fix.yml@main"
    "ci-auto-fix.yml|workflow_dispatch|workflow_dispatch trigger present"
    "ci-auto-fix.yml|domiva-agent-lab#5|workflow_run disabled with issue reference"
  )

  local issues=0

  echo ""
  echo "Agent workflow health check: $repo"
  echo ""

  # 1. Workflow files present
  echo "Workflow files:"
  for file in "${WORKFLOW_FILES[@]}"; do
    local dest="$workflows_dir/$file"
    if [[ -f "$dest" ]]; then
      ok "$file exists"
    else
      fail "$file missing"
      (( issues++ ))
      if $cure; then
        local stack
        stack="$(detect_stack)"
        [[ -z "$stack" ]] && { warn "Cannot auto-detect stack — skipping cure for $file"; continue; }
        local new_content
        new_content="$(apply_template "$TEMPLATES_DIR/$file" "$stack")"
        show_diff_and_prompt "$dest" "$new_content" "$file" && (( issues-- )) || true
      fi
    fi
  done

  echo ""

  # 2. Structural checks
  echo "Workflow structure:"
  for check in "${DOCTOR_CHECKS[@]}"; do
    IFS='|' read -r file pattern description <<< "$check"
    local dest="$workflows_dir/$file"

    if [[ ! -f "$dest" ]]; then
      continue  # already reported as missing above
    fi

    if grep -q "$pattern" "$dest"; then
      ok "$file: $description"
    else
      fail "$file: $description"
      (( issues++ ))
      if $cure; then
        local stack
        stack="$(detect_stack)"
        if [[ -n "$stack" ]]; then
          local new_content
          new_content="$(apply_template "$TEMPLATES_DIR/$file" "$stack")"
          show_diff_and_prompt "$dest" "$new_content" "$file ($description)" && (( issues-- )) || true
        else
          warn "Cannot auto-detect stack — skipping cure for $file"
        fi
      fi
    fi
  done

  echo ""

  # 3. Secrets — check repo-level first, then org-level (org secrets are inherited)
  echo ""
  if $skip_secrets; then
    echo "Secrets: skipped (--skip-secrets)"
  else
    echo "Secrets ($repo):"
    local org
    org="$(echo "$repo" | cut -d'/' -f1)"
    local repo_secrets org_secrets all_secrets
    repo_secrets="$(gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null || echo "")"
    org_secrets="$(gh secret list --org "$org" --json name --jq '.[].name' 2>/dev/null || echo "")"
    all_secrets="$(printf '%s\n%s' "$repo_secrets" "$org_secrets")"

    for secret in "${REQUIRED_SECRETS[@]}"; do
      if echo "$all_secrets" | grep -qx "$secret"; then
        ok "$secret"
      else
        fail "$secret not configured (repo or org)"
        (( issues++ ))
        if $cure; then
          warn "Secrets must be set manually: gh secret set $secret --repo $repo"
        fi
      fi
    done
  fi

  echo ""

  if [[ $issues -eq 0 ]]; then
    echo "All checks passed."
  else
    echo "$issues issue(s) found."
    if ! $cure; then
      echo "Run 'agent-workflows.sh doctor --cure' to fix interactively."
    fi
    exit 1
  fi
}

# ─── entry point ──────────────────────────────────────────────────────────────

COMMAND="${1:-install}"
[[ $# -gt 0 ]] && shift || true

case "$COMMAND" in
  install)       cmd_install "$@" ;;
  doctor)        cmd_doctor  "$@" ;;
  -h|--help)     usage ;;
  *)             die "Unknown command: $COMMAND. Run with -h for help." ;;
esac
