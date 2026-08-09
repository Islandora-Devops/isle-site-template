#!/usr/bin/env bash

set -euo pipefail

starter_directory="${GITHUB_WORKSPACE}/.islandora-starter-site"
drupal_root="${PROJECT_DIRECTORY}/drupal/rootfs/var/www/drupal"
settings_path="${drupal_root}/assets/patches/default_settings.txt"
settings_backup="${RUNNER_TEMP}/isle-default-settings.txt"

if [ ! -d "$drupal_root" ] || [ ! -d "$starter_directory/.git" ]; then
  echo "::error::The selected repositories do not have the expected ISLE/starter-site layouts."
  exit 1
fi
if [ -f "$settings_path" ]; then
  cp "$settings_path" "$settings_backup"
fi

find "$drupal_root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
tar \
  --directory "$starter_directory" \
  --exclude .git \
  --exclude .github \
  --exclude ci \
  --exclude renovate.json5 \
  --create --file - . | tar --directory "$drupal_root" --extract --file -

mkdir -p \
  "${drupal_root}/web/modules/custom" \
  "${drupal_root}/web/themes/custom"
touch \
  "${drupal_root}/web/modules/custom/.gitkeep" \
  "${drupal_root}/web/themes/custom/.gitkeep"
if [ -f "$settings_backup" ]; then
  mkdir -p "$(dirname "$settings_path")"
  cp "$settings_backup" "$settings_path"
fi
