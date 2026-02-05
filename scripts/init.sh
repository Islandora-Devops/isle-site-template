#!/usr/bin/env bash

set -eou pipefail

env_created=false
if [ ! -f .env ]; then
  cp sample.env .env
  env_created=true
fi


# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if [ -n "${ISLANDORA_TAG:-}" ]; then
  update_env ISLANDORA_TAG "\"${ISLANDORA_TAG}\""
fi

# Determine if fresh initialization is needed
needs_fresh_init=false
if $env_created; then
  needs_fresh_init=true
  echo_e "${YELLOW}No .env file found. Starting fresh installation...${RESET}"
elif ! check_volumes_exist "$COMPOSE_PROJECT_NAME"; then
  needs_fresh_init=true
  echo_e "${YELLOW}Docker volumes not found for project '${COMPOSE_PROJECT_NAME}'. Site needs initialization...${RESET}"
fi

if $needs_fresh_init; then
  # Prompt for configuration unless non-interactive
  if ! is_noninteractive; then
    echo ""
    echo_e "${BLUE}=== ISLE Site Configuration ===${RESET}"
    echo "Configure your site settings (press Enter to accept defaults):"
    echo ""

    NEW_PROJECT_NAME=$(prompt_with_default "Compose project name" "$COMPOSE_PROJECT_NAME")
    NEW_DOMAIN=$(prompt_with_default "Site domain" "$DOMAIN")

    # Update .env if values changed
    if [ "$NEW_PROJECT_NAME" != "$COMPOSE_PROJECT_NAME" ]; then
      update_env "COMPOSE_PROJECT_NAME" "$NEW_PROJECT_NAME"
    fi
    if [ "$NEW_DOMAIN" != "$DOMAIN" ]; then
      update_env "DOMAIN" "$NEW_DOMAIN"
    fi

    echo ""
    echo_e "${GREEN}Configuration saved to .env${RESET}"

    # Re-source profile.sh to pick up new values
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"
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
