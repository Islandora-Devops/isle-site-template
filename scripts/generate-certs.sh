#!/usr/bin/env bash
# shellcheck shell=bash

set -euf -o pipefail

if [ "${URI_SCHEME:-http}" != "https" ] || [ "${TLS_PROVIDER:-self-managed}" != "self-managed" ]; then
  # Compose mounts these files even with ACME or HTTP. Empty files are ignored
  # by the container certificate importer.
  mkdir -p certs
  for path in certs/cert.pem certs/rootCA.pem certs/privkey.pem; do
    if [ ! -e "$path" ] || { [ -f "$path" ] && [ "$(wc -c < "$path")" -eq 32 ] && grep -Eq '^[A-Za-z0-9]{32}$' "$path"; }; then
      : > "$path"
    fi
  done
  exit 0
fi

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

if [ -f "${PROGDIR}/certs/rootCA.pem" ] && ! openssl x509 -in "${PROGDIR}/certs/rootCA.pem" -noout >/dev/null 2>&1; then
  if [ ! -s "${PROGDIR}/certs/rootCA.pem" ] || { [ "$(wc -c < "${PROGDIR}/certs/rootCA.pem")" -eq 32 ] && grep -Eq '^[A-Za-z0-9]{32}$' "${PROGDIR}/certs/rootCA.pem"; }; then
    cp "${CAROOT}/rootCA.pem" "${PROGDIR}/certs/rootCA.pem"
  else
    echo "Invalid existing certificate material: ${PROGDIR}/certs/rootCA.pem" >&2
    exit 1
  fi
elif [ ! -f "${PROGDIR}/certs/rootCA.pem" ]; then
  cp "${CAROOT}/rootCA.pem" "${PROGDIR}/certs/rootCA.pem"
fi

DOMAIN_NAMES=("${DOMAIN:-islandora.io}" "*.${DOMAIN:-islandora.io}")

mkcert -cert-file certs/cert.pem -key-file certs/privkey.pem \
  "${DOMAIN_NAMES[@]}" \
  "*.islandora.io" \
  "islandora.io" \
  "*.islandora.info" \
  "islandora.info" \
  "localhost" \
  "127.0.0.1" \
  "::1"

echo "Certificates generated successfully."
