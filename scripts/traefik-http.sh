#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

echo "${BLUE}Switching to HTTP mode...${RESET}"

sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="false"/' .env && rm -f .env.bak
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="http"/' .env && rm -f .env.bak
sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="false"/' .env && rm -f .env.bak
if grep -q '^DOMAIN=islandora.dev' .env; then
    sed -i.bak 's/^DOMAIN=.*/DOMAIN=islandora.traefik.me/' .env && rm -f .env.bak
    echo "Domain changed from islandora.dev to islandora.traefik.me"
fi

echo "Done! HTTP mode enabled. Run:"
echo "${BLUE}docker compose down traefik"
echo "${BLUE}make up{RESET}"
echo "for changes to take effect."
