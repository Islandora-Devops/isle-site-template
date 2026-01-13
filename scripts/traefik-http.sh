#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

echo "${BLUE}Switching to HTTP mode...${RESET}"

sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="false"/' .env && rm -f .env.bak
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="http"/' .env && rm -f .env.bak
sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="false"/' .env && rm -f .env.bak

set_https "false"
set_letsencrypt_config "false"

echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
