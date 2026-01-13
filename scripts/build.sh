#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

find drupal/rootfs -type d -exec chmod 755 {} \;
find drupal/rootfs -type f -exec chmod 644 {} \;
chmod +x ./drupal/rootfs/etc/s6-overlay/s6-rc.d/install/up \
         ./drupal/rootfs/etc/s6-overlay/scripts/install.sh

docker compose build

# copy the container drupal root to the host
# to make editing from the host IDE easy
if [ "$DEVELOPMENT_ENVIRONMENT" = "true" ]; then
    rm -rf ./drupal/rootfs/var/www/drupal
    mkdir -p ./drupal/rootfs/var/www/drupal
    CONTAINER=$(docker create "${REPOSITORY}/${COMPOSE_PROJECT_NAME}:${TAG}")
    docker cp "${CONTAINER}:/var/www/drupal/." ./drupal/rootfs/var/www/drupal/
    docker rm "${CONTAINER}"
fi
