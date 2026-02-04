#!/usr/bin/env bash

set -eou pipefail

SEQUEL_ACE_PATH="/Applications/Sequel Ace.app"

if [ ! -d "$SEQUEL_ACE_PATH" ]; then
    echo "Error: Sequel Ace is not installed at $SEQUEL_ACE_PATH" >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

mariadb_db=drupal_default
mariadb_user=drupal_default
mariadb_password=$(cat secrets/DRUPAL_DEFAULT_DB_PASSWORD)

open "mysql://${mariadb_user}:${mariadb_password}@127.0.0.1:3306/${mariadb_db}" -a "$SEQUEL_ACE_PATH"

