#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
COMPOSER_JSON="${PROJECT_ROOT}/drupal/rootfs/var/www/drupal/composer.json"

prompt() {
  local label="$1"
  local default_value="${2:-}"
  local reply

  if [ -n "$default_value" ]; then
    read -r -p "${label} [${default_value}]: " reply
    printf "%s\n" "${reply:-$default_value}"
  else
    read -r -p "${label}: " reply
    printf "%s\n" "$reply"
  fi
}

parse_github_pr() {
  local input="$1"

  if [[ "$input" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+)(\.patch)?(/.*)?$ ]]; then
    GITHUB_OWNER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]}"
    GITHUB_PR="${BASH_REMATCH[3]}"
  elif [[ "$input" =~ ^([^/]+)/([^/#]+)#([0-9]+)$ ]]; then
    GITHUB_OWNER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]}"
    GITHUB_PR="${BASH_REMATCH[3]}"
  else
    printf "Expected a GitHub PR URL like https://github.com/OWNER/REPO/pull/123.\n" >&2
    return 1
  fi

  GITHUB_REPO="${GITHUB_REPO%.git}"
  PATCH_URL="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/pull/${GITHUB_PR}.patch"
}

validate_composer_package() {
  local composer_package="$1"

  if ! [[ "$composer_package" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf "Composer package must look like vendor/package.\n" >&2
    return 1
  fi
}

detect_composer_package() {
  local repo="$1"
  local composer_package

  composer_package="$(
    awk -F '"' -v suffix="/${repo}" '
      length($2) >= length(suffix) && substr($2, length($2) - length(suffix) + 1) == suffix {
        print $2
        exit
      }
    ' "$COMPOSER_JSON"
  )"

  printf "%s\n" "${composer_package:-drupal/${repo}}"
}

update_composer_patch() {
  local composer_package="$1"
  local patch_label="$2"
  local patch_url="$3"
  local yq_image="${YQ_IMAGE:-islandora/base:main}"

  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e COMPOSER_PACKAGE="$composer_package" \
    -e PATCH_LABEL="$patch_label" \
    -e PATCH_URL="$patch_url" \
    -v "$PROJECT_ROOT:/workspace:rw" \
    -w /workspace \
    --entrypoint yq \
    "$yq_image" \
    -o=json -I=4 -i \
    '.extra.patches[strenv(COMPOSER_PACKAGE)][strenv(PATCH_LABEL)] = strenv(PATCH_URL)' \
    drupal/rootfs/var/www/drupal/composer.json
}

main() {
  local pr_input
  local default_patch_label
  local composer_package
  local patch_label

  cd "$PROJECT_ROOT"

  if [ ! -f "$COMPOSER_JSON" ]; then
    printf "Cannot find %s.\n" "$COMPOSER_JSON" >&2
    return 1
  fi

  pr_input="${GITHUB_PR_URL:-$(prompt "GitHub PR URL or .patch URL")}"
  parse_github_pr "$pr_input"

  default_patch_label="${GITHUB_OWNER}/${GITHUB_REPO} PR #${GITHUB_PR}"

  composer_package="${COMPOSER_PACKAGE:-$(detect_composer_package "$GITHUB_REPO")}"
  validate_composer_package "$composer_package"

  patch_label="${PATCH_LABEL:-$default_patch_label}"

  update_composer_patch "$composer_package" "$patch_label" "$PATCH_URL"

  printf "Added Composer patch for %s:\n" "$composer_package"
  printf "  %s: %s\n" "$patch_label" "$PATCH_URL"

  if [ "${SKIP_BUILD_UP:-false}" = "true" ]; then
    printf "SKIP_BUILD_UP=true, so make build up was not run.\n"
  else
    make build up
  fi
}

main "$@"
