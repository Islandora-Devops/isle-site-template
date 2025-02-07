#!/usr/bin/env bash

set -eou pipefail

ISLANDORA_STARTER_REF="${ISLANDORA_STARTER_REF:=heads/main}"
ISLANDORA_STARTER_OWNER="${ISLANDORA_STARTER_OWNER:=islandora-devops}"
ISLANDORA_TAG="${ISLANDORA_TAG:=main}"

# allow passing "destroy" to this script to cleanup past runs locally
if [ $# -eq 1 ] && [ "$1" = "destroy" ]; then
  rm -rf drupal
  git checkout -- drupal
  docker compose --profile dev down --volumes
fi

# save the site template default settings.php
# so we can overwrite it for the starter site
mv drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt .
curl -L "https://github.com/${ISLANDORA_STARTER_OWNER}/islandora-starter-site/archive/refs/${ISLANDORA_STARTER_REF}.tar.gz" \
  | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
mv default_settings.txt drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt

# copy any drush scripts into the rootfs so we can run them
cp ./tests/solr.php drupal/rootfs/var/www/drupal/

./generate-certs.sh
./generate-secrets.sh

docker compose --profile dev build --pull
docker compose --profile dev pull || echo "continuing"
docker compose --profile dev up -d

echo "Waiting for installation..."
docker compose --profile dev exec drupal-dev timeout 600 bash -c "while ! test -f /installed; do sleep 5; done"

./tests/ping.sh

docker compose --profile dev exec drupal-dev drush scr solr.php

docker compose --profile dev down
