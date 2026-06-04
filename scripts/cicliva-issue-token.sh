#!/usr/bin/env bash
# cicliva-issue-token.sh — issue a Cicliva access token to a beta tester
#
# Usage:
#   cicliva-issue-token.sh              Issue a new token (guided browser flow)
#   cicliva-issue-token.sh list         List all issued tokens
#   cicliva-issue-token.sh revoke NAME  Revoke a token by customer name
#   cicliva-issue-token.sh -h|--help    Show this help

set -euo pipefail

ISSUED_DIR="$HOME/.cicliva/issued"
CICLIVA_ORG="cicliva"
CICLIVA_REPO="cicliva-workflows"
DEFAULT_EXPIRY_DAYS=90

# ── helpers ───────────────────────────────────────────────────────────────────

die()  { echo "error: $*" >&2; exit 1; }
ok()   { echo "  ✓ $*"; }
info() { echo "  → $*"; }

usage() {
  cat <<'EOF'
cicliva-issue-token.sh — issue Cicliva access tokens to beta testers

Usage:
  cicliva-issue-token.sh              Issue a new token (guided browser flow)
  cicliva-issue-token.sh list         List all issued tokens and expiry dates
  cicliva-issue-token.sh revoke NAME  Mark a token revoked by customer name
  cicliva-issue-token.sh -h|--help    Show this help

Tokens are fine-grained GitHub PATs scoped to cicliva/cicliva-workflows (read-only).
GitHub does not support creating these via API — this script guides you through
the browser flow and records the result locally.

Issued token records are stored in ~/.cicliva/issued/.
EOF
  exit 0
}

open_url() {
  local url="$1"
  if command -v open &>/dev/null; then
    open "$url"
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url" 2>/dev/null
  else
    echo "  Open this URL in your browser:"
    echo "  $url"
  fi
}

# ── token record format ───────────────────────────────────────────────────────
# ~/.cicliva/issued/{slug}.env
# CUSTOMER_NAME=...
# CUSTOMER_EMAIL=...
# ISSUED_DATE=YYYY-MM-DD
# EXPIRY_DATE=YYYY-MM-DD
# STATUS=active|revoked
# NOTE=...   (optional)

slug_for() {
  echo "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-'
}

# ── commands ──────────────────────────────────────────────────────────────────

cmd_issue() {
  mkdir -p "$ISSUED_DIR"
  chmod 700 "$ISSUED_DIR"

  echo ""
  echo "Cicliva — Issue Beta Access Token"
  echo ""

  # Collect customer info
  printf "Customer name: "
  read -r CUSTOMER_NAME
  [[ -n "$CUSTOMER_NAME" ]] || die "Name cannot be empty."

  printf "Customer email: "
  read -r CUSTOMER_EMAIL
  [[ -n "$CUSTOMER_EMAIL" ]] || die "Email cannot be empty."

  printf "Expiry in days [${DEFAULT_EXPIRY_DAYS}]: "
  read -r EXPIRY_INPUT
  EXPIRY_DAYS="${EXPIRY_INPUT:-$DEFAULT_EXPIRY_DAYS}"

  ISSUED_DATE=$(date +%Y-%m-%d)
  EXPIRY_DATE=$(date -v "+${EXPIRY_DAYS}d" +%Y-%m-%d 2>/dev/null || date -d "+${EXPIRY_DAYS} days" +%Y-%m-%d)

  printf "Note (optional): "
  read -r NOTE

  echo ""
  echo "────────────────────────────────────────────────────────"
  echo "You need to create a fine-grained PAT in the GitHub UI."
  echo "Opening browser to: github.com/settings/personal-access-tokens/new"
  echo ""
  echo "Use these exact settings:"
  echo ""
  echo "  Token name:       cicliva-${CUSTOMER_NAME// /-}-${ISSUED_DATE}"
  echo "  Expiration:       Custom → ${EXPIRY_DATE}"
  echo "  Resource owner:   ${CICLIVA_ORG}"
  echo "  Repository:       Only select repositories → ${CICLIVA_REPO}"
  echo "  Permissions:"
  echo "    Contents        → Read-only"
  echo "    Metadata        → Read-only (required)"
  echo ""
  echo "Click 'Generate token', then paste it below."
  echo "────────────────────────────────────────────────────────"
  echo ""

  open_url "https://github.com/settings/personal-access-tokens/new"

  # Read token with masked input
  local TOKEN=""
  while [[ -z "$TOKEN" ]]; do
    read -rs -p "Paste token (hidden): " TOKEN
    echo ""
    [[ -z "$TOKEN" ]] && echo "  Token cannot be empty."
  done

  # Validate token against the repo
  info "Validating token..."
  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/${CICLIVA_ORG}/${CICLIVA_REPO}" 2>/dev/null || echo "000")

  if [[ "$http_code" == "200" ]]; then
    ok "Token validated — has read access to ${CICLIVA_ORG}/${CICLIVA_REPO}"
  elif [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    die "Token rejected — verify permissions and try again."
  elif [[ "$http_code" == "404" ]]; then
    die "Token cannot see ${CICLIVA_ORG}/${CICLIVA_REPO} — check Resource owner and repo selection."
  else
    die "Could not reach GitHub (HTTP $http_code) — check your connection."
  fi

  # Save record
  local SLUG
  SLUG=$(slug_for "$CUSTOMER_NAME")
  local RECORD_FILE="$ISSUED_DIR/${SLUG}.env"

  # Handle duplicate slugs
  if [[ -f "$RECORD_FILE" ]]; then
    RECORD_FILE="$ISSUED_DIR/${SLUG}-${ISSUED_DATE}.env"
  fi

  cat > "$RECORD_FILE" <<EOF
CUSTOMER_NAME=${CUSTOMER_NAME}
CUSTOMER_EMAIL=${CUSTOMER_EMAIL}
ISSUED_DATE=${ISSUED_DATE}
EXPIRY_DATE=${EXPIRY_DATE}
STATUS=active
NOTE=${NOTE}
EOF
  chmod 600 "$RECORD_FILE"

  # Save token separately (extra restricted)
  local TOKEN_FILE="$ISSUED_DIR/${SLUG}.token"
  [[ -f "$TOKEN_FILE" ]] && TOKEN_FILE="$ISSUED_DIR/${SLUG}-${ISSUED_DATE}.token"
  echo "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"

  echo ""
  ok "Token recorded: $RECORD_FILE"
  echo ""
  echo "Send this to ${CUSTOMER_NAME}:"
  echo ""
  echo "────────────────────────────────────────────────────────"
  echo "Your Cicliva access token:"
  echo ""
  echo "  $TOKEN"
  echo ""
  echo "Install Cicliva agent workflows:"
  echo ""
  echo "  curl -fsSL https://storage.googleapis.com/cicliva-scripts/cicliva-setup.sh | bash"
  echo ""
  echo "When prompted, paste the token above."
  echo "Expires: ${EXPIRY_DATE}"
  echo "────────────────────────────────────────────────────────"
  echo ""
}

cmd_list() {
  mkdir -p "$ISSUED_DIR"

  echo ""
  echo "Issued Cicliva tokens:"
  echo ""

  local found=0
  for record in "$ISSUED_DIR"/*.env; do
    [[ -f "$record" ]] || { echo "  (none)"; echo ""; return; }
    found=1

    # shellcheck disable=SC1090
    source "$record"
    local status_icon="✓"
    [[ "$STATUS" == "revoked" ]] && status_icon="✗"

    printf "  %s  %-25s  %-30s  expires %s  [%s]\n" \
      "$status_icon" "$CUSTOMER_NAME" "$CUSTOMER_EMAIL" "$EXPIRY_DATE" "$STATUS"

    [[ -n "$NOTE" ]] && echo "       Note: $NOTE"
  done

  [[ $found -eq 0 ]] && echo "  (none)"
  echo ""
}

cmd_revoke() {
  local name="$1"
  [[ -n "$name" ]] || die "Usage: cicliva-issue-token.sh revoke <customer-name>"

  local slug
  slug=$(slug_for "$name")
  local record="$ISSUED_DIR/${slug}.env"

  if [[ ! -f "$record" ]]; then
    # Try date-suffixed variants
    local match
    match=$(ls "$ISSUED_DIR/${slug}"-*.env 2>/dev/null | head -1 || echo "")
    [[ -n "$match" ]] && record="$match" || die "No token record found for: $name"
  fi

  # shellcheck disable=SC1090
  source "$record"

  sed -i '' 's/^STATUS=.*/STATUS=revoked/' "$record" 2>/dev/null \
    || sed -i 's/^STATUS=.*/STATUS=revoked/' "$record"

  echo ""
  ok "Marked as revoked: $CUSTOMER_NAME ($CUSTOMER_EMAIL)"
  echo ""
  echo "To actually invalidate the token, delete it from GitHub:"
  echo "  https://github.com/settings/personal-access-tokens"
  echo "(Find the token named cicliva-${CUSTOMER_NAME// /-}-*)"
  echo ""
}

# ── entry point ───────────────────────────────────────────────────────────────

case "${1:-issue}" in
  issue)         cmd_issue ;;
  list)          cmd_list ;;
  revoke)        shift; cmd_revoke "${1:-}" ;;
  -h|--help)     usage ;;
  *)             die "Unknown command: $1. Use -h for help." ;;
esac
