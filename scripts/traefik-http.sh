#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

echo "${BLUE}Switching to HTTP mode...${RESET}"

update_env ENABLE_HTTPS "false"
update_env URI_SCHEME "http"
update_env ENABLE_ACME "false"

set_https "false"
set_letsencrypt_config "false"

echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
