#!/usr/bin/env bash
# shellcheck shell=bash

set -euf -o pipefail

if ! command -v mkcert &> /dev/null; then
  echo "${RED}Error: mkcert is not installed or not in PATH${RESET}"
  exit 1
fi

echo "Generating certificates with mkcert..."

PROGDIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
readonly PROGDIR

CAROOT=$(mkcert -CAROOT)
readonly CAROOT

timeout 10 mkcert -install || true

if [ ! -f "${PROGDIR}/certs/rootCA-key.pem" ]; then
  cp "${CAROOT}/rootCA-key.pem" "${PROGDIR}/certs/rootCA-key.pem"
fi

if [ ! -f "${PROGDIR}/certs/rootCA.pem" ]; then
  cp "${CAROOT}/rootCA.pem" "${PROGDIR}/certs/rootCA.pem"
fi

mkcert -cert-file certs/cert.pem -key-file certs/privkey.pem \
  "*.islandora.io" \
  "islandora.io" \
  "*.islandora.info" \
  "islandora.info" \
  "*.islandora.traefik.me" \
  "islandora.traefik.me" \
  "localhost" \
  "127.0.0.1" \
  "::1"

echo "Certificates generated successfully."
