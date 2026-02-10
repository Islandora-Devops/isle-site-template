#!/usr/bin/env bash

set -eou pipefail

extend_healthcheck=false
if [ ! -f .env ]; then
  cp sample.env .env
  extend_healthcheck=true
fi

if [ -n "${ISLANDORA_TAG:-}" ]; then
  sed -i.bak "s|^ISLANDORA_TAG=.*|ISLANDORA_TAG=\"${ISLANDORA_TAG}\"|" .env
  rm -f .env.bak
fi

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

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
