#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

MAX_RETRIES=${MAX_RETRIES:-10}
SLEEP_INCREMENT=5
RETRIES=0
while true; do
    timeout 5 curl -fs "$URI_SCHEME://$DOMAIN/" | grep Islandora && break || exit_code=$?

    RETRIES=$((RETRIES + 1))
    if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
        echo "Site failed to come online after $MAX_RETRIES attempts (Last exit code: $exit_code)." >&2
        exit 1
    fi

    SLEEP=$(( SLEEP_INCREMENT * RETRIES ))
    echo "Site is not live yet. Retrying in $SLEEP seconds... (Attempt $RETRIES/$MAX_RETRIES)" >&2
    sleep "$SLEEP"
done
