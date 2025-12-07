#!/usr/bin/env bash
# shellcheck shell=bash
set -euf -o pipefail

RESET=$(tput sgr0)
RED=$(tput setaf 9)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 6)
readonly RESET RED GREEN BLUE

# Parse flags
ISLE_SITE_TEMPLATE_REF=""
STARTER_SITE_BRANCH=""
STARTER_SITE_OWNER="Islandora-Devops"
SITE_NAME=""

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
    --site-name=*)
      SITE_NAME="${arg#*=}"
      shift
      ;;
    *)
      # Unknown option; ignore or handle as needed.
      ;;
  esac
done

# For some commands we must invoke a Windows executable if in the context of WSL.
IS_WSL=$(grep -q WSL /proc/version 2>/dev/null && echo "true" || echo "false")
readonly IS_WSL
if [[ "${IS_WSL}" == "true" ]]; then
  MKCERT=mkcert.exe
else
  MKCERT=mkcert
fi

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
    "${MKCERT}"
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

function valid_repository_name {
  local name="${1}"
  echo "${name}" | awk '/^[a-zA-Z0-9_-]+$/' | grep . &>/dev/null
  return $?
}

function get_repository_name {
  # If SITE_NAME flag is provided, use it.
  if [[ -n "${SITE_NAME}" ]]; then
    if ! valid_repository_name "${SITE_NAME}"; then
      echo "Invalid repository name ${SITE_NAME} (Only alpha-numeric, underscores, and hyphens allowed)"
      exit 1
    fi
    echo "${SITE_NAME}"
    return
  fi
  # Otherwise prompt the user.
  read -r -p "Please enter a name for your new git repository: " name
  if ! valid_repository_name "${name}"; then
    echo "Invalid repository name ${name} (Only alpha-numeric, underscores, and hyphens allowed)"
    exit 1
  fi
  echo "${name}"
}

function create_repository {
  local repository
  repository=$(get_repository_name)
  echo "Creating new repository: ${repository}..."
  mkdir -p "${repository}"
  pushd "${repository}" 2>/dev/null
  git init
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

function initialize_from_site_template {
  local repo="https://github.com/Islandora-Devops/isle-site-template"
  local ref
  echo "Initializing from site template..."
  # Use --isle-site-template-ref flag if provided; otherwise, prompt.
  if [[ -n "${ISLE_SITE_TEMPLATE_REF}" ]]; then
    ref="${ISLE_SITE_TEMPLATE_REF}"
  else
    ref=$(choose_ref "${repo}")
  fi
  curl -L "${repo}/archive/${ref}.tar.gz" | tar -xz --strip-components=1
  rm -fr .github setup.sh tests
  cp sample.env .env
  mv docker-compose.sample.yml docker-compose.override.yml
  git add .
  git commit -am "First commit, added isle-site-template."
}

function initialize_from_starter_site {
  local repo="https://github.com/${STARTER_SITE_OWNER}/islandora-starter-site"
  local ref
  echo "Initializing from starter site..."
  # Use --starter-site-branch flag if provided; otherwise, prompt.
  if [[ -n "${STARTER_SITE_BRANCH}" ]]; then
    ref="${STARTER_SITE_BRANCH}"
  else
    ref=$(choose_ref "${repo}")
  fi
  curl -L "${repo}/archive/${ref}.tar.gz" \
    | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
  rm -fr drupal/rootfs/var/www/drupal/.github
  git checkout drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt
  git add .
  git commit -am "Second commit, added isle-starter-site."
}

function generate_certs {
  ./generate-certs.sh
}

function generate_secrets {
  ./generate-secrets.sh
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
    create_repository
    initialize_from_site_template
    initialize_from_starter_site
    generate_certs
    generate_secrets
  else
    exit 1
  fi
}

main
