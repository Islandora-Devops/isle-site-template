#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

if ! command -v mkcert &> /dev/null; then
  echo "Error: mkcert is not installed"
  echo "Please install mkcert from: https://github.com/FiloSottile/mkcert#installation"
  exit 1
fi

echo "${BLUE}Switching to HTTPS mode with mkcert...${RESET}"

sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^TLS_PROVIDER=.*/TLS_PROVIDER="self-managed"/' .env && rm -f .env.bak

set_https "true"
set_letsencrypt_config "false"

export CAROOT=./certs
mkcert -install || sudo mkcert -install

echo "Done! HTTPS mode enabled with mkcert certificates."
echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
