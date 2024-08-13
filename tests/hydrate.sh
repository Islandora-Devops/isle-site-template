#!/usr/bin/env bash

set -eou pipefail

docker pull jcorall/islandora-workbench:latest

sed_cross_platform() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sed -i "$@"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        echo "Unsupported OS"
        return 1
    fi
}

# setup a sample ingest
if [ ! -d islandora_workbench_demo_content ]; then
  git clone https://github.com/DonRichards/islandora_workbench_demo_content
fi
sed_cross_platform 's#^host.*#host: https://islandora.dev/#g' islandora_workbench_demo_content/example_content.yml
sed_cross_platform 's/^username.*/username: admin/g' islandora_workbench_demo_content/example_content.yml
sed_cross_platform "s/^password.*/password: $(cat ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)/g" islandora_workbench_demo_content/example_content.yml
sed_cross_platform 's/islandora_workbench_demo_content/data/g' islandora_workbench_demo_content/example_content.yml
DRUPAL_CONTAINER=$(docker container ls --format "{{ .Names }}" | grep drupal)
docker exec "$DRUPAL_CONTAINER" drush user:password admin "$(cat ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)"

# run the ingest
docker run \
  --rm \
  --network="host" \
  -v "$(pwd)/islandora_workbench_demo_content":/workbench/data \
  --name wb \
  jcorall/islandora-workbench:latest \
  bash -lc "python3 workbench --config /workbench/data/example_content.yml"

echo "Wait 120s for derivatives to be created"
sleep 120

docker container ls
# print all the files in the system by mimetype
docker exec "$DRUPAL_CONTAINER" drush sqlq "SELECT filemime, COUNT(*) FROM file_managed GROUP BY filemime ORDER BY COUNT(*) DESC"

# make sure 21 OCR files were created
OCR_FILES=$(docker exec "$DRUPAL_CONTAINER" drush sqlq "SELECT filemime, COUNT(*) FROM file_managed GROUP BY filemime ORDER BY COUNT(*) DESC" | grep "text/plain")
if [ "$OCR_FILES" != "21" ]; then
  echo "Should be 21 OCR files"
  exit 1
fi

# print all the media use in the system
docker exec "$DRUPAL_CONTAINER" drush sqlq "SELECT t.name, COUNT(*) FROM media__field_media_use u INNER JOIN taxonomy_term_field_data t ON t.tid = field_media_use_target_id GROUP BY tid"
THUMBNAIL_MEDIA=$(docker exec "$DRUPAL_CONTAINER" drush sqlq "SELECT t.name, COUNT(*) FROM media__field_media_use u INNER JOIN taxonomy_term_field_data t ON t.tid = field_media_use_target_id GROUP BY tid" | grep Thumbnail | awk '{print $3}')
if [ "$THUMBNAIL_MEDIA" != "36" ]; then
  echo "Should be 36 thumbnail images"
  exit 1
fi
