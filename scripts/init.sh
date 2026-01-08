#!/usr/bin/env bash

set -eou pipefail

find drupal/rootfs -type d -exec chmod 755 {} \;

if [ ! -f .env ]; then
  cp sample.env .env;
fi
if [ -n "${ISLANDORA_TAG:-}" ]; then
  sed -i.bak "s|^ISLANDORA_TAG=.*|ISLANDORA_TAG=\"${ISLANDORA_TAG}\"|" .env
  rm -f .env.bak
fi

id -u > ./certs/UID

docker compose run --rm init

chown -R "$(whoami)" ./certs ./secrets || sudo chown -R "$(whoami)" ./certs ./secrets

make build
