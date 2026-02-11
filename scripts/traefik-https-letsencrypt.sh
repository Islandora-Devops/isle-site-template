#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

# Get the public IP of the current host
get_public_ip() {
  curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
  curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
  curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
  echo ""
}

# Verify DNS records required for Let's Encrypt
verify_dns() {
  local domain="$1"
  local errors=0

  echo_e "${BLUE}Verifying DNS records for Let's Encrypt...${RESET}"

  local public_ip
  public_ip=$(get_public_ip)
  if [ -z "$public_ip" ]; then
    echo_e "${YELLOW}Warning: Could not determine public IP. Skipping DNS verification.${RESET}"
    return 0
  fi
  echo "  Public IP: $public_ip"

  # Required domains: main domain and fcrepo subdomain
  local required_domains=("$domain" "fcrepo.$domain")

  for host in "${required_domains[@]}"; do
    local resolved_ip
    resolved_ip=$(get_dns_ip "$host")

    if [ -z "$resolved_ip" ]; then
      echo_e "  ${RED}✗ $host - does not resolve${RESET}"
      errors=$((errors + 1))
    elif [ "$resolved_ip" != "$public_ip" ]; then
      echo_e "  ${RED}✗ $host - resolves to $resolved_ip (expected $public_ip)${RESET}"
      errors=$((errors + 1))
    else
      echo_e "  ${GREEN}✓ $host - resolves to $resolved_ip${RESET}"
    fi
  done

  if [ $errors -gt 0 ]; then
    echo ""
    echo_e "${RED}DNS verification failed.${RESET}"
    echo "Ensure the following DNS records point to $public_ip:"
    for host in "${required_domains[@]}"; do
      echo "  - $host"
    done
    echo ""
    echo "Let's Encrypt requires valid DNS records to issue certificates."
    return 1
  fi

  echo_e "${GREEN}DNS verification passed.${RESET}"
  return 0
}

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

# Verify DNS before proceeding
echo
if ! verify_dns "$NEW_DOMAIN"; then
  exit 1
fi

echo
echo "Updating .env with:"
echo "  ${GREEN}URI_SCHEME=https"
echo "  DOMAIN=${NEW_DOMAIN}"
echo "  ACME_EMAIL=${NEW_EMAIL}"
echo "  DEVELOPMENT_ENVIRONMENT=false${RESET}"
echo

update_env DEVELOPMENT_ENVIRONMENT "false"
update_env DOMAIN "$NEW_DOMAIN"
update_env ACME_EMAIL "$NEW_EMAIL"

set_https "true"
set_letsencrypt_config "true"

echo "Site will be available at: ${GREEN}${URI_SCHEME}://${NEW_DOMAIN}${RESET}"
echo "Run this for the changes to take effect (will result in ~2m site down time):"
echo "${BLUE}make down-traefik up"

# we first recycle traefik so it can come up with the new ACME config
# we should wait until traefik gets its new certs
# there isn't an easy way to detect that
# so we just wait 60s and then recycle the entire stack
# to ensure all containers have the proper CA
echo "sleep 60 && make down up${RESET}"

