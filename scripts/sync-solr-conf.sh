#!/usr/bin/env bash

set -euo pipefail

echo "Refreshing Solr core config from the running drupal container..."

SOLR_CONF_HOST_PATH="drupal/rootfs/opt/solr/server/solr/default/conf"
SOLR_CONF_CONTAINER_PATH="/opt/solr/server/solr/default/conf"
DRUPAL_CONTAINER_ID="$(docker compose ps -q drupal)"

if [ -z "${DRUPAL_CONTAINER_ID}" ]; then
  echo "Could not determine the drupal container ID."
  exit 1
fi

docker compose exec -T drupal with-contenv bash -lc \
  "for_all_sites create_solr_core_with_default_config"

rm -rf "${SOLR_CONF_HOST_PATH}"
docker cp "${DRUPAL_CONTAINER_ID}:${SOLR_CONF_CONTAINER_PATH}" "${SOLR_CONF_HOST_PATH}"

echo "Solr core config refresh complete."
