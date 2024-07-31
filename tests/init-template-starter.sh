#!/usr/bin/env bash

set -eou pipefail

if [ ! -v ISLANDORA_STARTER_REF ] || [ "$ISLANDORA_STARTER_REF" = "" ]; then
  ISLANDORA_STARTER_REF=heads/main
fi

if [ ! -v ISLANDORA_TAG ] || [ "$ISLANDORA_TAG" = "" ]; then
  ISLANDORA_TAG=main
fi

# save the site template default settings.php
# so we can overwrite it for the starter site
mv drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt .
curl -L "https://github.com/Islandora-Devops/islandora-starter-site/archive/refs/${ISLANDORA_STARTER_REF}.tar.gz" \
  | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
mv default_settings.txt drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt

# copy any drush scripts into the rootfs so we can run them
cp ./tests/solr.php drupal/rootfs/var/www/drupal/

./generate-certs.sh
./generate-secrets.sh

docker compose --profile dev up -d

./tests/ping.sh

docker compose --profile dev exec drupal-dev drush scr solr.php
