#!/usr/bin/env bash

set -eou pipefail

cd /

if [ "${URI_SCHEME:-http}" = "https" ] && [ "${TLS_PROVIDER:-self-managed}" = "self-managed" ]; then
    apk add nss-tools

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  PLATFORM="amd64" ;;
        aarch64|arm64) PLATFORM="arm64" ;;
        *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    curl -JL "https://dl.filippo.io/mkcert/latest?for=linux/$PLATFORM" -o /usr/local/bin/mkcert
    chmod +x /usr/local/bin/mkcert

    ./scripts/generate-certs.sh
fi

./scripts/generate-secrets.sh
