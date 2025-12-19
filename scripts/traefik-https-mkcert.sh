#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

echo "${BLUE}Switching to HTTPS mode with mkcert...${RESET}"

sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="true"/' .env && rm -f .env.bak
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="false"/' .env && rm -f .env.bak
sed -i.bak 's/^DOMAIN=.*/DOMAIN=islandora.dev/' .env && rm -f .env.bak

echo "Done! HTTPS mode enabled with mkcert certificates."
echo "Site will be available at: https://islandora.dev"
echo "Run ${BLUE}make down${RESET} up Traefik for changes to take effect."
