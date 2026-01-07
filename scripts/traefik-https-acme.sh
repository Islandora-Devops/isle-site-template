#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

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
echo "  DOMAIN=${NEW_DOMAIN}"
echo "  ACME_EMAIL=${NEW_EMAIL}"
echo

# Update .env file
sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="true"/' .env && rm -f .env.bak
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="true"/' .env && rm -f .env.bak
sed -i.bak "s|^DOMAIN=.*|DOMAIN=${NEW_DOMAIN}|" .env && rm -f .env.bak
sed -i.bak "s|^ACME_EMAIL=.*|ACME_EMAIL=${NEW_EMAIL}|" .env && rm -f .env.bak

echo "Configuration updated successfully!"
echo "Run ${BLUE}docker compose down traefik && make up${RESET} for changes to take effect."
