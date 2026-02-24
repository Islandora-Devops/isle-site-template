#!/usr/bin/env bash

set -eou pipefail

SEQUEL_ACE_PATH="/Applications/Sequel Ace.app"

if [ ! -d "$SEQUEL_ACE_PATH" ]; then
    echo "Error: Sequel Ace is not installed at $SEQUEL_ACE_PATH" >&2
    exit 1
fi

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/profile.sh"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Support both .yml and .yaml extensions
if [ -f "$PROJECT_ROOT/docker-compose.override.yml" ]; then
    OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yml"
elif [ -f "$PROJECT_ROOT/docker-compose.override.yaml" ]; then
    OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yaml"
else
    OVERRIDE_FILE=""
fi

if [ -z "$OVERRIDE_FILE" ]; then
    echo "${RED}Error: docker-compose.override.yml does not exist.${RESET}" >&2
    echo "" >&2
    echo "To enable mariadb port mapping, run:" >&2
    echo -e "\t${BLUE}cp docker-compose.dev.yml docker-compose.override.yml" >&2
    echo -e "\tmake up${RESET}" >&2
    exit 1
fi

# Check if mariadb has port 3306 mapped
if ! grep -A5 'mariadb:' "$OVERRIDE_FILE" | grep -q '3306:3306'; then
    echo "${RED}Error: mariadb port 3306 is not mapped to host in docker-compose.override.yml${RESET}" >&2
    echo "" >&2
    echo "To enable mariadb port mapping, run:" >&2
    echo -e "\t${BLUE}cp docker-compose.dev.yml docker-compose.override.yml" >&2
    echo -e "\tmake up${RESET}" >&2
    exit 1
fi


mariadb_db=drupal_default
mariadb_user=drupal_default
mariadb_password=$(cat secrets/DRUPAL_DEFAULT_DB_PASSWORD)

open "mysql://${mariadb_user}:${mariadb_password}@127.0.0.1:3306/${mariadb_db}" -a "$SEQUEL_ACE_PATH"

