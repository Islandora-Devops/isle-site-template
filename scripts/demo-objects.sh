#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if [ ! -d "islandora_workbench" ]; then
  git clone https://github.com/mjordan/islandora_workbench
fi

if [ ! -d "islandora_demo_objects" ]; then
  git clone https://github.com/Islandora-Devops/islandora_demo_objects islandora_demo_objects
fi

URI_PORT=$(traefik_port_80)
if [ "${URI_SCHEME}" = "https" ]; then
  URI_PORT=$(traefik_port_443)
fi

URL="${URI_SCHEME}://${DOMAIN}"
if [ "${URI_PORT}" != "80" ] && [ "${URI_PORT}" != "443" ]; then
  URL="${URL}:${URI_PORT}"
fi

sed -i.bak \
  -e "s#^host.*#host: ${URL}/#g" \
  -e "s#^input_csv.*#input_csv: /islandora_demo_objects/create_islandora_objects.csv#g" \
  -e "s#^input_dir.*#input_dir: /islandora_demo_objects/#g" \
  -e '/password:/d' \
  islandora_demo_objects/create_islandora_objects.yml

docker build \
  --build-arg USER_ID="$(id -u)" \
  --build-arg GROUP_ID="$(id -u)" \
  -t workbench-docker:latest \
  islandora_workbench

docker run \
  -it \
  --rm \
  --env ISLANDORA_WORKBENCH_PASSWORD="$(cat secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)" \
  --network="host" \
  -v "$(pwd)/islandora_workbench":/workbench \
  -v "$(pwd)/islandora_demo_objects":/islandora_demo_objects \
  --name my-running-workbench \
  workbench-docker:latest \
  bash -lc "./workbench --config /islandora_demo_objects/create_islandora_objects.yml"
