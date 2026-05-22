#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
OVERRIDE_FILE="${PROJECT_ROOT}/docker-compose.override.yml"
DEV_OVERRIDE_FILE="${PROJECT_ROOT}/docker-compose.dev.yml"
CHECKOUT_ROOT="${PROJECT_ROOT}/drupal-projects"

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

normalize_source() {
  local source="$1"
  case "$source" in
    drupal | d | drupal.org)
      printf "drupal\n"
      ;;
    islandora | i | github)
      printf "islandora\n"
      ;;
    custom | c | url)
      printf "custom\n"
      ;;
    *)
      printf "Unknown source '%s'. Use drupal, islandora, or custom.\n" "$source" >&2
      return 1
      ;;
  esac
}

github_repo_to_url() {
  local repo="$1"

  case "$repo" in
    https://* | http://* | git@* | ssh://*)
      printf "%s\n" "$repo"
      ;;
    */*)
      printf "https://github.com/%s.git\n" "${repo%.git}"
      ;;
    *)
      printf "https://github.com/Islandora/%s.git\n" "${repo%.git}"
      ;;
  esac
}

remote_default_branch() {
  local repo_url="$1"
  local default_branch

  default_branch="$(git ls-remote --symref "$repo_url" HEAD 2>/dev/null | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }' || true)"
  printf "%s\n" "${default_branch:-main}"
}

validate_extension_name() {
  local extension_name="$1"

  if [ -z "$extension_name" ]; then
    printf "Extension name is required.\n" >&2
    return 1
  fi

  if ! [[ "$extension_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    printf "Extension name may only contain letters, numbers, dots, underscores, and dashes.\n" >&2
    return 1
  fi
}

checkout_branch() {
  local checkout_dir="$1"
  local branch="$2"

  if git -C "$checkout_dir" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "$checkout_dir" checkout "$branch"
  elif git -C "$checkout_dir" show-ref --verify --quiet "refs/remotes/origin/${branch}"; then
    git -C "$checkout_dir" checkout -b "$branch" "origin/${branch}"
  else
    git -C "$checkout_dir" checkout "$branch"
  fi
}

clone_or_update_repo() {
  local repo_url="$1"
  local branch="$2"
  local checkout_dir="$3"
  local existing_origin
  local update_origin

  mkdir -p "$(dirname "$checkout_dir")"

  if [ -d "${checkout_dir}/.git" ]; then
    existing_origin="$(git -C "$checkout_dir" remote get-url origin 2>/dev/null || true)"
    if [ -n "$existing_origin" ] && [ "$existing_origin" != "$repo_url" ]; then
      update_origin="$(prompt "Existing checkout uses origin '${existing_origin}'. Update origin to '${repo_url}'? (y/N)" "N")"
      case "$update_origin" in
        y | Y | yes | YES)
          git -C "$checkout_dir" remote set-url origin "$repo_url"
          ;;
        *)
          printf "Keeping existing origin '%s'.\n" "$existing_origin"
          ;;
      esac
    fi
    git -C "$checkout_dir" fetch origin --prune
  elif [ -e "$checkout_dir" ]; then
    printf "Cannot clone into '%s' because it exists and is not a git checkout.\n" "$checkout_dir" >&2
    return 1
  else
    git clone "$repo_url" "$checkout_dir"
    git -C "$checkout_dir" fetch origin --prune
  fi

  checkout_branch "$checkout_dir" "$branch"
}

detect_extension_type() {
  local checkout_dir="$1"
  local detected_type

  detected_type="$(
    find "$checkout_dir" -maxdepth 1 -name '*.info.yml' -type f -print0 |
      xargs -0 awk -F ':' '/^[[:space:]]*type[[:space:]]*:/ {
        value=$2
        gsub(/^[[:space:]"'"'"']+|[[:space:]"'"'"']+$/, "", value)
        if (value == "module" || value == "theme") {
          print value
          exit
        }
      }' 2>/dev/null || true
  )"

  printf "%s\n" "$detected_type"
}

normalize_extension_type() {
  local extension_type="$1"
  case "$extension_type" in
    module | m)
      printf "module\n"
      ;;
    theme | t)
      printf "theme\n"
      ;;
    *)
      printf "Unknown extension type '%s'. Use module or theme.\n" "$extension_type" >&2
      return 1
      ;;
  esac
}

ensure_override_file() {
  if [ -L "$OVERRIDE_FILE" ]; then
    local tmp_file="${OVERRIDE_FILE}.tmp"
    cp "$OVERRIDE_FILE" "$tmp_file"
    rm "$OVERRIDE_FILE"
    mv "$tmp_file" "$OVERRIDE_FILE"
    printf "Converted docker-compose.override.yml symlink to a local editable file.\n"
  elif [ ! -e "$OVERRIDE_FILE" ]; then
    if [ -f "$DEV_OVERRIDE_FILE" ]; then
      cp "$DEV_OVERRIDE_FILE" "$OVERRIDE_FILE"
      printf "Created docker-compose.override.yml from docker-compose.dev.yml.\n"
    else
      printf "services:\n  drupal:\n    volumes:\n" > "$OVERRIDE_FILE"
      printf "Created minimal docker-compose.override.yml.\n"
    fi
  fi
}

upsert_drupal_volume() {
  local mount_spec="$1"
  local target_path="$2"
  local yq_image="${YQ_IMAGE:-islandora/base:main}"

  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e TARGET_PATH="$target_path" \
    -e MOUNT_SPEC="$mount_spec" \
    -v "$PROJECT_ROOT:/workspace:rw" \
    -w /workspace \
    --entrypoint yq \
    "$yq_image" \
    -i '
    .services.drupal.volumes = (
      (.services.drupal.volumes // [])
      | map(select(
          if type == "!!map" then
            .target != strenv(TARGET_PATH)
          else
            (tostring | contains(":" + strenv(TARGET_PATH)) | not)
          end
        ))
      + [strenv(MOUNT_SPEC)]
    )
  ' docker-compose.override.yml
}

configure_bind_mount() {
  local checkout_dir="$1"
  local extension_name="$2"
  local extension_type="$3"
  local mount_source
  local target_path
  local mount_spec

  mount_source="./${checkout_dir#"$PROJECT_ROOT"/}"
  case "$extension_type" in
    module)
      target_path="/var/www/drupal/web/modules/contrib/${extension_name}"
      ;;
    theme)
      target_path="/var/www/drupal/web/themes/contrib/${extension_name}"
      ;;
  esac

  mount_spec="${mount_source}:${target_path}:z,rw,\${CONSISTENCY}"

  ensure_override_file
  upsert_drupal_volume "$mount_spec" "$target_path"

  printf "Bind mounted %s to %s in docker-compose.override.yml.\n" "$mount_source" "$target_path"
}

main() {
  local extension_name
  local default_source
  local source
  local repo_prompt_default
  local repo_answer
  local repo_url
  local default_branch
  local branch
  local checkout_dir
  local detected_type
  local extension_type

  cd "$PROJECT_ROOT"

  extension_name="${DRUPAL_EXTENSION_NAME:-$(prompt "Module/theme machine name")}"
  validate_extension_name "$extension_name"

  default_source="drupal"
  if [[ "$extension_name" == islandora* ]]; then
    default_source="islandora"
  fi
  source="$(normalize_source "${DRUPAL_EXTENSION_SOURCE:-$(prompt "Project source (drupal, islandora, custom)" "$default_source")}")"

  case "$source" in
    drupal)
      repo_url="https://git.drupalcode.org/project/${extension_name}.git"
      ;;
    islandora)
      repo_prompt_default="Islandora/${extension_name}"
      repo_answer="${DRUPAL_EXTENSION_REPO:-$(prompt "GitHub repository or URL" "$repo_prompt_default")}"
      repo_url="$(github_repo_to_url "$repo_answer")"
      ;;
    custom)
      repo_url="${DRUPAL_EXTENSION_REPO:-$(prompt "Git repository URL")}"
      ;;
  esac

  default_branch="$(remote_default_branch "$repo_url")"
  branch="${DRUPAL_EXTENSION_BRANCH:-$(prompt "Branch" "$default_branch")}"

  checkout_dir="${CHECKOUT_ROOT}/${extension_name}"
  clone_or_update_repo "$repo_url" "$branch" "$checkout_dir"

  detected_type="$(detect_extension_type "$checkout_dir")"
  extension_type="$(normalize_extension_type "${DRUPAL_EXTENSION_TYPE:-$(prompt "Extension type (module/theme)" "${detected_type:-module}")}")"

  configure_bind_mount "$checkout_dir" "$extension_name" "$extension_type"

  if [ "${SKIP_MAKE_UP:-false}" = "true" ]; then
    printf "SKIP_MAKE_UP=true, so make up was not run.\n"
  else
    make up
  fi
}

main "$@"
