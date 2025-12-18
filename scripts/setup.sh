#!/usr/bin/env bash
# shellcheck shell=bash
set -euf -o pipefail

if [ "${GITHUB_ACTIONS:-}" != "" ]; then
  set -x
fi

RESET=$(tput sgr0)
RED=$(tput setaf 9)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 6)
readonly RESET RED GREEN BLUE

# Parse flags
ISLE_SITE_TEMPLATE_OWNER="${ISLE_SITE_TEMPLATE_OWNER:-Islandora-Devops}"
ISLE_SITE_TEMPLATE_REF="${ISLE_SITE_TEMPLATE_REF:-}"
STARTER_SITE_BRANCH="${STARTER_SITE_BRANCH:-}"
STARTER_SITE_OWNER="${STARTER_SITE_OWNER:-Islandora-Devops}"

for arg in "$@"; do
  case $arg in
    --isle-site-template-ref=*)
      ISLE_SITE_TEMPLATE_REF="${arg#*=}"
      shift
      ;;
    --starter-site-branch=*)
      STARTER_SITE_BRANCH="${arg#*=}"
      shift
      ;;
    --starter-site-owner=*)
      STARTER_SITE_OWNER="${arg#*=}"
      shift
      ;;
    *)
      # Unknown option; ignore or handle as needed.
      ;;
  esac
done

function executable_exists {
  local executable="${1}"
  if ! command -v "${executable}" >/dev/null; then
    return 1
  fi
  return 0
}

function has_prerequisites {
  local executables=(
    "docker"
  )
  for executable in "${executables[@]}"; do
    if ! executable_exists "${executable}"; then
      cat <<-EOT >&2
${RED}Could not find executable: ${executable}${RESET}
${BLUE}Consult the README.md for how to install requirements.${RESET}
EOT
      return 1
    fi
  done
  echo "Prerequisites found..."
  return 0
}

function get_refs {
  local repository="${1}"
  echo "refs/heads/main" # Only interested in the main branch.
  git ls-remote --sort=-version:refname "${repository}" 'refs/tags/*' | cut -f2
}

function choose_ref {
  local repository="${1}"
  local refs=()
  local display=()
  local display_ref
  while IFS='' read -r line; do refs+=("$line"); done < <(get_refs "${repository}")
  # Only show the user the interesting part of the ref.
  for ref in "${refs[@]}"; do
    display_ref=$(echo "${ref}" | sed -e 's/^.*\/\([^\/]*\)$/\1/g')
    display+=("${display_ref}")
  done
  PS3="Choose a branch/tag from ${repository##*/}: "
  select ref in "${display[@]}"; do
    echo "${refs[$REPLY - 1]}"
    return
  done
}

function set_site_template_files {
  cp sample.env .env
  if [[ -n "${ISLANDORA_TAG:-}" ]]; then
    sed -i.bak "s|^ISLANDORA_TAG=.*|ISLANDORA_TAG=\"${ISLANDORA_TAG}\"|" .env && rm -f .env.bak
  fi
  mv docker-compose.sample.yml docker-compose.override.yml
}
function initialize_from_site_template {
  if [ -f ./docker-compose.yml ]; then
    set_site_template_files
    return 0
  fi

  local repo="https://github.com/${ISLE_SITE_TEMPLATE_OWNER}/isle-site-template"
  local ref
  echo "Initializing from site template..."
  # Use --isle-site-template-ref flag if provided; otherwise, prompt.
  if [[ -n "${ISLE_SITE_TEMPLATE_REF}" ]]; then
    ref="${ISLE_SITE_TEMPLATE_REF#heads/}"
    ref="${ref#tags/}"
  else
    ref=$(choose_ref "${repo}")
  fi
  curl -L "${repo}/archive/${ref#refs/}.tar.gz" | tar -xz --strip-components=1
  rm -fr .github
  set_site_template_files
}

function initialize_from_starter_site {
  local repo="https://github.com/${STARTER_SITE_OWNER}/islandora-starter-site"
  local ref
  cp drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt .
  echo "Initializing from starter site..."
  # Use --starter-site-branch flag if provided; otherwise, prompt.
  if [[ -n "${STARTER_SITE_BRANCH}" ]]; then
    ref="${STARTER_SITE_BRANCH#heads/}"
    ref="${ref#tags/}"
  else
    ref=$(choose_ref "${repo}")
  fi
  curl -L "${repo}/archive/${ref#refs/}.tar.gz" \
    | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
  rm -fr drupal/rootfs/var/www/drupal/.github
  mv default_settings.txt drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt
}

function main {
  cat <<-EOT
${GREEN}
#################################
# Setting up isle-site-template #
#################################
${RESET}
EOT
  if has_prerequisites; then
    initialize_from_site_template
    initialize_from_starter_site
    make init
  else
    exit 1
  fi
}

main
