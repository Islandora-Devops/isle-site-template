#!/usr/bin/env bash

set -eou pipefail

need_init=false
if [ ! -f .env ]; then
  cp sample.env .env
  need_init=true
fi

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if [ -n "${ISLANDORA_TAG:-}" ]; then
  update_env ISLANDORA_TAG "\"${ISLANDORA_TAG}\""
fi

if ! check_volumes_exist "$COMPOSE_PROJECT_NAME"; then
  need_init=true
fi

if $need_init; then
  if ! is_noninteractive; then
    echo ""
    echo_e "${BLUE}=== ISLE Site Configuration ===${RESET}"
    echo "Configure your site settings (press Enter to accept defaults):"
    echo ""

    NEW_PROJECT_NAME=$(prompt_with_default "Compose project name" "$COMPOSE_PROJECT_NAME")
    NEW_DOMAIN=$(prompt_with_default "Site domain" "$DOMAIN")

    if [ "$NEW_PROJECT_NAME" != "$COMPOSE_PROJECT_NAME" ]; then
      if [[ ! "$NEW_PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]; then
        echo "Invalid project name. Must be alphanumeric, hyphens, and underscores only (max 64 chars)."
        exit 1
      fi
      update_env "COMPOSE_PROJECT_NAME" "$NEW_PROJECT_NAME"
    fi

    if [ "$NEW_DOMAIN" != "$DOMAIN" ]; then
      IP=$(get_dns_ip "$NEW_DOMAIN")
      if [ -z "$IP" ]; then
        echo "Invalid domain name. Was unable to resolve the domain to an IP address."
        exit 1
      fi
      update_env "DOMAIN" "$NEW_DOMAIN"
    fi

    echo ""
    echo_e "${GREEN}Configuration saved to .env${RESET}"
    export_env

  else
    echo_e "${YELLOW}Running in non-interactive mode, using defaults from .env${RESET}"
  fi

  # Extend healthcheck for fresh install
  update_env DRUPAL_HEALTHCHECK_RETRIES 10
  update_env DRUPAL_HEALTHCHECK_START_PERIOD 1m
fi

if is_dev_mode && is_docker_rootless; then
  echo "Development mode is not supported on rootless docker."
  echo "You must set DEVELOPMENT_ENVIRONMENT=false in .env"
  exit 0
fi

# For SELinux if applicable.
if command -v "sestatus" >/dev/null; then
  if sestatus | grep -q "SELinux status: *enabled"; then
    if command -v "chcon" >/dev/null; then
      PROGDIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd | xargs dirname)"
      sudo chcon -R -t container_file_t "${PROGDIR}/secrets" || true
      sudo chcon -R -t container_file_t "${PROGDIR}/certs" || true
    fi
  fi
fi

docker compose run --rm init

chown -R "$(whoami)" ./certs ./secrets > /dev/null 2>&1 || sudo chown -R "$(whoami)" ./certs ./secrets

make build
