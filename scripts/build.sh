#!/usr/bin/env bash

set -eou pipefail

find drupal/rootfs -type d -exec chmod 755 {} \;

docker compose build

