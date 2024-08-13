#!/usr/bin/env bash

set -eou pipefail

# install workbench
git clone https://github.com/mjordan/islandora_workbench
cd islandora_workbench
docker build -t workbench:latest .

# setup a sample ingest
git clone https://github.com/DonRichards/islandora_workbench_demo_content
sed -i 's#^host.*#host: https://islandora.dev/#g' islandora_workbench_demo_content/example_content.yml
sed -i 's/^username.*/username: admin/g' islandora_workbench_demo_content/example_content.yml
sed -i 's/^password.*/password: "'"$(cat ../secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)"'"/g' islandora_workbench_demo_content/example_content.yml

# run the ingest
docker run \
  --rm \
  --network="host" \
  -v "$(pwd)":/workbench \
  --name wb \
  workbench:latest \
  bash -lc "python3 workbench --config /workbench/islandora_workbench_demo_content/example_content.yml"

# Wait for derivatives to be created
sleep 30

DRUPAL_CONTAINER=$(docker container ls --format "{{ .Names }}" | grep drupal)
docker exec "$DRUPAL_CONTAINER" drush sqlq "SELECT filemime, COUNT(*) FROM file_managed GROUP BY filemime ORDER BY COUNT(*) DESC"
