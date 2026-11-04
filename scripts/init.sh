#!/usr/bin/env bash

set -eou pipefail

need_init=false
extend_healthcheck=false
if [ ! -f .env ]; then
  cp sample.env .env
  need_init=true
  extend_healthcheck=true
fi

if [ -n "${ISLANDORA_TAG:-}" ]; then
  sed -i.bak "s|^ISLANDORA_TAG=.*|ISLANDORA_TAG=\"${ISLANDORA_TAG}\"|" .env
  rm -f .env.bak
fi

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

# A copied .env is not proof that the project has been initialized. Check its
# named volumes too, since users often copy the sample file before first start.
if ! docker volume ls -q 2>/dev/null | grep -q "^${COMPOSE_PROJECT_NAME}_mariadb-data$"; then
  need_init=true
fi

if $need_init && [ -t 0 ] && [ "${ISLE_SITE_TEMPLATE_NONINTERACTIVE:-false}" != "true" ]; then
  read -r -p "Compose project name [${COMPOSE_PROJECT_NAME}]: " new_project
  read -r -p "Site domain [${DOMAIN}]: " new_domain
  [ -n "$new_project" ] && update_env COMPOSE_PROJECT_NAME "$new_project"
  [ -n "$new_domain" ] && update_env DOMAIN "$new_domain"
  # Refresh values exported by profile.sh after changing .env.
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"
fi

if $extend_healthcheck; then
  # we've detected an initial install
  # so extend the default start period for drupal's healthcheck to 1m
  # so it has time to come online before docker compose marks it unhealthy
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
