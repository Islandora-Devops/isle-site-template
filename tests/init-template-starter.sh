#!/usr/bin/env bash

set -eou pipefail

ISLANDORA_STARTER_REF="${ISLANDORA_STARTER_REF:=heads/main}"
ISLANDORA_STARTER_OWNER="${ISLANDORA_STARTER_OWNER:=islandora-devops}"
ISLE_SITE_TEMPLATE_REF="${ISLE_SITE_TEMPLATE_REF:=main}"
GITHUB_ACTIONS="${GITHUB_ACTIONS:=false}"

# allow passing "destroy" to this script to cleanup past runs locally
if [ $# -eq 1 ] && [ "$1" = "destroy" ]; then
  if [ -d ist-test ]; then
    docker compose --profile dev -f ist-test/docker-compose.yml down --volumes
    rm -rf ist-test
  fi
fi

./setup.sh \
  --isle-site-template-ref="$ISLE_SITE_TEMPLATE_REF" \
  --starter-site-owner="${ISLANDORA_STARTER_OWNER}" \
  --starter-site-branch="${ISLANDORA_STARTER_REF#*/}" \
  --site-name=ist-test

# copy any drush scripts into the rootfs so we can run them
cp ./tests/solr.php ist-test/drupal/rootfs/var/www/drupal/

docker compose -f ist-test/docker-compose.yml --profile dev up --pull=always --build -d

echo "Waiting for installation..."
docker compose -f ist-test/docker-compose.yml --profile dev exec drupal-dev timeout 600 bash -c "while ! test -f /installed; do sleep 5; done"

./tests/ping.sh

docker compose -f ist-test/docker-compose.yml --profile dev exec drupal-dev drush scr solr.php

if [ "$GITHUB_ACTIONS" = "false" ]; then
  docker compose -f ist-test/docker-compose.yml --profile dev down
fi
