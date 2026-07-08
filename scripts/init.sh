#!/usr/bin/env bash

set -eou pipefail

extend_healthcheck=false

set_env_value() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
    rm -f .env.bak
    return
  fi
  printf '%s=%s\n' "${key}" "${value}" >> .env
}

is_docker_rootless() {
  docker info -f "{{println .SecurityOptions}}" 2>/dev/null | grep -qi rootless
}

is_dev_mode() {
  local value
  value="$(sed -n 's/^DEVELOPMENT_ENVIRONMENT=//p' .env | tail -n 1 | tr -d "\"'[:space:]")"
  [ "${value:-false}" = "true" ]
}

if [ ! -f .env ]; then
  cp sample.env .env
  extend_healthcheck=true
fi

if [ -n "${ISLANDORA_TAG:-}" ]; then
  set_env_value ISLANDORA_TAG "${ISLANDORA_TAG}"
fi

if $extend_healthcheck; then
  # we've detected an initial install
  # so extend the default start period for drupal's healthcheck to 1m
  # so it has time to come online before docker compose marks it unhealthy
  set_env_value DRUPAL_HEALTHCHECK_RETRIES 10
  set_env_value DRUPAL_HEALTHCHECK_START_PERIOD 1m
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

chown -R "$(whoami)" ./certs ./secrets > /dev/null 2>&1 || sudo chown -R "$(whoami)" ./certs ./secrets > /dev/null 2>&1 || true

mkdir -p ./certs
id -u > ./certs/UID
if [ -d drupal/rootfs ]; then
  find drupal/rootfs -type d -exec chmod 755 {} \;
fi
docker compose pull --ignore-buildable --ignore-pull-failures
docker compose build
