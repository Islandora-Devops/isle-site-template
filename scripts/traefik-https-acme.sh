#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

echo "Switching to HTTPS mode with ACME (Let's Encrypt)..."

sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="true"/' .env && rm -f .env.bak
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="true"/' .env && rm -f .env.bak

echo "IMPORTANT: Make sure to configure ACME_EMAIL in .env before starting!"
echo "Run ${BLUE}make down${RESET} up Traefik for changes to take effect."
