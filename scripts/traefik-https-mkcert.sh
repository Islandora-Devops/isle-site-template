#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if is_wsl; then
  echo "${RED}Error: mkcert is not supported using WSL. Stay on http for local development.${RESET}"
  exit 0
fi

echo "${BLUE}Switching to HTTPS mode with mkcert...${RESET}"

# Update .env file
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^TLS_PROVIDER=.*/TLS_PROVIDER="self-managed"/' .env && rm -f .env.bak
set_https "true"
set_letsencrypt_config "false"

PROGDIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
readonly PROGDIR
"${PROGDIR}/scripts/generate-certs.sh"

echo ""
echo "${GREEN}Done! HTTPS mode enabled with mkcert certificates.${RESET}"
echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo ""
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
