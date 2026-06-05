#!/usr/bin/env bash
# cicliva-setup.sh — first-time setup and updates for Cicliva customers
#
# Usage:
#   cicliva-setup.sh            First-time setup: validate token, mirror workflow
#                               library into your org, and install workflows
#   cicliva-setup.sh --update   Pull latest cicliva-workflows into your org's copy
#   cicliva-setup.sh -h|--help  Show this help

set -euo pipefail

CICLIVA_DIR="$HOME/.cicliva"
TOKEN_FILE="$CICLIVA_DIR/token"
SHA_FILE="$CICLIVA_DIR/repo-sha"
ORG_FILE="$CICLIVA_DIR/org"
CICLIVA_SOURCE="cicliva/cicliva-workflows"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GCS_BASE="https://storage.googleapis.com/cicliva-public-scripts"

# ── helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "  ✓ $*"; }
fail() { echo "  ✗ $*"; }
info() { echo "  → $*"; }
die()  { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
cicliva-setup.sh — Cicliva workflow platform setup

Usage:
  cicliva-setup.sh             First-time setup
  cicliva-setup.sh --update    Pull latest updates into your org's copy
  cicliva-setup.sh -h|--help   Show this help

First-time setup:
  Prompts for your Cicliva access token, creates a private cicliva-workflows
  repo in your org, mirrors the workflow library into it, and installs the
  workflow files into this repo.

Updates:
  Uses your saved token to pull the latest from cicliva/cicliva-workflows
  and push it to your org's copy. Run agent-workflows.sh doctor --cure
  afterward to apply any workflow file changes to this repo.
EOF
  exit 0
}

# ── token ─────────────────────────────────────────────────────────────────────

ensure_token() {
  mkdir -p "$CICLIVA_DIR"
  chmod 700 "$CICLIVA_DIR"

  if [[ -f "$TOKEN_FILE" ]]; then
    TOKEN=$(cat "$TOKEN_FILE")
    return
  fi

  echo ""
  echo "A Cicliva access token is required to continue."
  echo "If you don't have one, contact adam@cicliva.com to get access."
  echo ""
  echo "Enter your Cicliva access token:"
  read -rs TOKEN < /dev/tty
  echo ""

  [[ -n "$TOKEN" ]] || die "Token cannot be empty."
  echo "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
}

validate_token() {
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$CICLIVA_SOURCE" 2>/dev/null)

  if [[ "$http_code" == "200" ]]; then
    ok "Token valid"
  elif [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    rm -f "$TOKEN_FILE"
    die "Token rejected — check your token and try again."
  elif [[ "$http_code" == "404" ]]; then
    rm -f "$TOKEN_FILE"
    die "Token does not have access to cicliva-workflows — contact Cicliva support."
  else
    die "Could not reach GitHub (HTTP $http_code) — check your connection."
  fi
}

# ── org ───────────────────────────────────────────────────────────────────────

ensure_org() {
  if [[ -f "$ORG_FILE" ]]; then
    CUSTOMER_ORG=$(head -1 "$ORG_FILE")
    IS_PERSONAL=$(grep '^IS_PERSONAL=' "$ORG_FILE" 2>/dev/null | cut -d'=' -f2 || echo "false")
    return
  fi

  local personal_login orgs
  personal_login=$(gh api /user --jq '.login' 2>/dev/null || echo "")
  orgs=$(gh api /user/orgs --jq '.[].login' 2>/dev/null || echo "")

  echo ""
  echo "Which account should cicliva-workflows be installed in?"
  echo "    $personal_login (personal)"
  if [[ -n "$orgs" ]]; then
    echo "$orgs" | while read -r org; do echo "    $org (org)"; done
  fi
  echo ""
  printf "Account: "
  read -r CUSTOMER_ORG < /dev/tty

  [[ -n "$CUSTOMER_ORG" ]] || die "Account cannot be empty."

  # Detect if personal account
  if [[ "$CUSTOMER_ORG" == "$personal_login" ]]; then
    IS_PERSONAL="true"
  else
    IS_PERSONAL="false"
  fi

  printf '%s\nIS_PERSONAL=%s\n' "$CUSTOMER_ORG" "$IS_PERSONAL" > "$ORG_FILE"
}

# ── mirror ────────────────────────────────────────────────────────────────────

mirror_repo() {
  local target_repo="$CUSTOMER_ORG/cicliva-workflows"

  info "Creating $target_repo (private)..."
  if [[ "$IS_PERSONAL" == "true" ]]; then
    gh api "user/repos" --method POST \
      --field name=cicliva-workflows \
      --field private=true \
      --field description="Cicliva agent workflow platform — private workflow library" \
      2>/dev/null || info "Repository already exists"
  else
    gh api "orgs/$CUSTOMER_ORG/repos" --method POST \
      --field name=cicliva-workflows \
      --field private=true \
      --field description="Cicliva agent workflow platform — private workflow library" \
      2>/dev/null || info "Repository already exists"
  fi

  info "Mirroring $CICLIVA_SOURCE → $target_repo..."

  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" EXIT

  git clone --quiet \
    "https://x-access-token:${TOKEN}@github.com/${CICLIVA_SOURCE}.git" \
    "$tmpdir/source"

  local sha
  sha=$(git -C "$tmpdir/source" rev-parse HEAD)

  git -C "$tmpdir/source" remote add customer \
    "https://x-access-token:$(gh auth token)@github.com/${target_repo}.git"
  git -C "$tmpdir/source" push customer main --force --quiet

  echo "$sha" > "$SHA_FILE"
  ok "Mirrored at ${sha:0:8}"
}

check_for_updates() {
  [[ -f "$SHA_FILE" ]] || return

  local local_sha remote_sha
  local_sha=$(cat "$SHA_FILE")
  remote_sha=$(curl -sf \
    -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$CICLIVA_SOURCE/commits/main" \
    2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha',''))" 2>/dev/null || echo "")

  if [[ -n "$remote_sha" && "$local_sha" != "$remote_sha" ]]; then
    echo ""
    echo "  ⚠ Updates available in cicliva-workflows."
    echo "    Run: cicliva-setup.sh --update"
  fi
}

# ── helpers ───────────────────────────────────────────────────────────────────

# Run agent-workflows.sh — use the local copy if we're running from a clone,
# otherwise fetch from GCS. Customers running via curl-to-bash won't have a
# local copy; they should always be able to reach the public GCS URL.
run_agent_workflows() {
  if [[ -f "$SCRIPT_DIR/agent-workflows.sh" ]]; then
    bash "$SCRIPT_DIR/agent-workflows.sh" "$@"
  else
    bash <(curl -fsSL "$GCS_BASE/agent-workflows.sh") "$@"
  fi
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_install() {
  echo ""
  echo "Cicliva Setup"
  echo ""

  ensure_token
  validate_token
  ensure_org
  mirror_repo

  # agent-workflows.sh install derives the learnings key from the token hash
  # and sets it as a repo secret — no separate key issuance step needed.
  echo ""
  run_agent_workflows install \
    --workflow-repo "$CUSTOMER_ORG/cicliva-workflows"
}

cmd_update() {
  echo ""
  echo "Cicliva Update"
  echo ""

  [[ -f "$TOKEN_FILE" ]] || die "No token found — run cicliva-setup.sh first."
  [[ -f "$ORG_FILE" ]]   || die "No org found — run cicliva-setup.sh first."

  TOKEN=$(cat "$TOKEN_FILE")
  CUSTOMER_ORG=$(head -1 "$ORG_FILE")

  validate_token
  mirror_repo

  echo ""
  echo "cicliva-workflows updated."
  echo "Run this to apply any workflow file changes to this repo:"
  echo ""
  echo "  bash <(curl -fsSL $GCS_BASE/agent-workflows.sh) doctor --cure"
}

# ── entry point ───────────────────────────────────────────────────────────────

TOKEN=""
CUSTOMER_ORG=""
IS_PERSONAL="false"

case "${1:-}" in
  --update)   cmd_update ;;
  -h|--help)  usage ;;
  "")         cmd_install ;;
  *)          die "Unknown argument: $1. Use -h for help." ;;
esac
