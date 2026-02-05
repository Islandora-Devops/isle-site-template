#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if is_wsl; then
  echo "${RED}Error: letsencrypt is not supported using WSL.${RESET}"
  exit 1
fi

echo "Switching to HTTPS mode with ACME (Let's Encrypt)..."
echo

# Get current values from .env
CURRENT_DOMAIN=$(grep '^DOMAIN=' .env | cut -d= -f2)
CURRENT_EMAIL=$(grep '^ACME_EMAIL=' .env | cut -d= -f2)

# Prompt for DOMAIN
read -r -p "Enter domain name (current: ${CURRENT_DOMAIN}): " NEW_DOMAIN
NEW_DOMAIN=${NEW_DOMAIN:-$CURRENT_DOMAIN}

# Prompt for ACME_EMAIL
read -r -p "Enter email for Let's Encrypt notifications (current: ${CURRENT_EMAIL}): " NEW_EMAIL
NEW_EMAIL=${NEW_EMAIL:-$CURRENT_EMAIL}

echo
echo "Updating .env with:"
echo "  ${GREEN}URI_SCHEME=https"
echo "  DOMAIN=${NEW_DOMAIN}"
echo "  ACME_EMAIL=${NEW_EMAIL}"
echo "  URI_SCHEME=http"
echo "  DEVELOPMENT_ENVIRONMENT=false${RESET}"
echo

# Update .env file
sed -i.bak 's|^DEVELOPMENT_ENVIRONMENT=.*|DEVELOPMENT_ENVIRONMENT="false"|' .env && rm -f .env.bak
sed -i.bak "s|^DOMAIN=.*|DOMAIN=${NEW_DOMAIN}|" .env && rm -f .env.bak
sed -i.bak "s|^ACME_EMAIL=.*|ACME_EMAIL=${NEW_EMAIL}|" .env && rm -f .env.bak

set_https "true"
set_letsencrypt_config "true"

echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
