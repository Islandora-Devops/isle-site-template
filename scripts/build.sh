#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

id -u > ./certs/UID

find drupal/rootfs -type d -exec chmod 755 {} \;

docker compose build
