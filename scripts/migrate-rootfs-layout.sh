#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

replace_in_file() {
  local file="$1"
  local old="$2"
  local new="$3"

  if [ ! -f "${file}" ]; then
    return
  fi

  if ! grep -Fq "${old}" "${file}"; then
    return
  fi

  sed -i.bak "s|${old//|/\\|}|${new//|/\\|}|g" "${file}"
  rm -f "${file}.bak"
}

rename_env_var() {
  local file="$1"
  local old="$2"
  local new="$3"

  if [ ! -f "${file}" ]; then
    return
  fi

  if grep -Eq "^${new}=" "${file}"; then
    return
  fi

  if ! grep -Eq "^${old}=" "${file}"; then
    return
  fi

  sed -i.bak "s/^${old}=/${new}=/" "${file}"
  rm -f "${file}.bak"
}

OLD_DRUPAL_ROOT="drupal/rootfs/var/www/drupal"
OLD_ROOTFS="drupal/rootfs"

if [ -f "drupal/Dockerfile" ] && [ ! -e "Dockerfile" ]; then
  mv "drupal/Dockerfile" "Dockerfile"
fi

if [ -d "${OLD_DRUPAL_ROOT}" ]; then
  shopt -s dotglob nullglob
  for item in "${OLD_DRUPAL_ROOT}"/*; do
    base=$(basename "${item}")
    if [ "${base}" = "README.md" ] || [ "${base}" = "LICENSE" ] || [ "${base}" = "CONTRIBUTING.md" ]; then
      continue
    fi
    mv "${item}" .
  done
  shopt -u dotglob nullglob
fi

if [ -d "${OLD_ROOTFS}" ] && [ ! -e "rootfs" ]; then
  mv "${OLD_ROOTFS}" "rootfs"
fi

replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/assets" "./assets"
replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/composer.json" "./composer.json"
replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/composer.lock" "./composer.lock"
replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/config" "./config"
replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/web/modules/custom" "./web/modules/custom"
replace_in_file "docker-compose.override.yml" "./drupal/rootfs/var/www/drupal/web/themes/custom" "./web/themes/custom"

replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/assets" "./assets"
replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/composer.json" "./composer.json"
replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/composer.lock" "./composer.lock"
replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/config" "./config"
replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/web/modules/custom" "./web/modules/custom"
replace_in_file "docker-compose.dev.yml" "./drupal/rootfs/var/www/drupal/web/themes/custom" "./web/themes/custom"

rename_env_var ".env" "REPOSITORY" "DOCKER_REPOSITORY"

find drupal -depth -type d -empty -delete 2>/dev/null || true
if [ -d "drupal" ] && [ -z "$(find drupal -mindepth 1 -print -quit 2>/dev/null)" ]; then
  rmdir drupal
fi

cat <<'GITIGNORE_RECOMMENDATION'
Recommend adding this to .gitignore:
# gitignore template for Drupal 8 projects
#
# earlier versions of Drupal are tracked in `community/PHP/`
#
# follows official upstream conventions:
# https://www.drupal.org/docs/develop/using-composer

# Ignore configuration files that may contain sensitive information
/web/sites/*/*settings*.php
/web/sites/*/*services*.yml

# Ignore paths that may contain user-generated content
/web/sites/*/files
/web/sites/*/public
/web/sites/*/private
/web/sites/*/files-public
/web/sites/*/files-private

# Ignore paths that may contain temporary files
/web/sites/*/translations
/web/sites/*/tmp
/web/sites/*/cache

# Ignore drupal core (if not versioning drupal sources)
/web/vendor
/web/core
/web/modules/README.txt
/web/modules/contrib
/web/profiles/README.txt
/web/profiles/contrib
/web/sites/development.services.yml
/web/sites/example.settings.local.php
/web/sites/example.sites.php
/web/sites/README.txt
/web/themes/README.txt
/web/themes/contrib
/web/.csslintrc
/web/.editorconfig
/web/.eslintignore
/web/.eslintrc.json
/web/.gitattributes
/web/.htaccess
/web/.ht.router.php
/web/autoload.php
/web/composer.json
/web/composer.lock
/web/example.gitignore
/web/index.php
/web/INSTALL.txt
/web/LICENSE.txt
/web/README.txt
/web/update.php
/web/web.config

# Ignore vendor dependencies and scripts
/vendor
/composer.phar
/composer
/robo.phar
/robo
/drush.phar
/drush
/drupal.phar
/drupal

docker-compose.override.yml
.env
islandora_workbench
islandora_demo_objects
GITIGNORE_RECOMMENDATION
