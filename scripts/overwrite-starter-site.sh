#!/usr/bin/env bash

set -eou pipefail

echo "Updating from islandora-starter-site..."

# We want to track the main branch of islandora-starter-site
# In the future, this could be changed to track latest release tag
STARTER_SITE_BRANCH="${STARTER_SITE_BRANCH:-main}"
STARTER_SITE_OWNER="${STARTER_SITE_OWNER:-islandora-devops}"

repo="https://github.com/${STARTER_SITE_OWNER}/islandora-starter-site"
ref="${STARTER_SITE_BRANCH}"

# The path to the drupal webroot
DRUPAL_ROOT="drupal/rootfs/var/www/drupal"

# Confirmation prompt if not in GitHub Actions
if [ "${GITHUB_ACTIONS:-}" == "" ]; then
  echo "This will overwrite the contents of '${DRUPAL_ROOT}'."
  read -p "Do you want to continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled by user."
    exit 1
  fi
fi

# Backup the settings file
if [ -f "${DRUPAL_ROOT}/assets/patches/default_settings.txt" ]; then
  mv "${DRUPAL_ROOT}/assets/patches/default_settings.txt" .
fi

rm -rf "${DRUPAL_ROOT}"
mkdir "${DRUPAL_ROOT}"

echo "Initializing from starter site..."
curl -sL "${repo}/archive/${ref}.tar.gz" \
  | tar --strip-components=1 -C "${DRUPAL_ROOT}" -xz

mkdir -p "${DRUPAL_ROOT}/web/modules/custom" \
      "${DRUPAL_ROOT}/web/themes/custom"

touch "${DRUPAL_ROOT}/web/modules/custom/.gitkeep" \
      "${DRUPAL_ROOT}/web/themes/custom/.gitkeep"

# Remove unnecessary files from starter site
rm -rf \
  "${DRUPAL_ROOT}/.github" \
  "${DRUPAL_ROOT}/.git" \
  "${DRUPAL_ROOT}/ci" \
  "${DRUPAL_ROOT}/renovate.json5"

# Restore the settings file
if [ -f "default_settings.txt" ]; then
  mv default_settings.txt "${DRUPAL_ROOT}/assets/patches/default_settings.txt"
fi

echo "Update from islandora-starter-site complete."
