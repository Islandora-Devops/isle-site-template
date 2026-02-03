#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

if ! command -v mkcert &> /dev/null; then
  echo "Error: mkcert is not installed"
  echo "Please install mkcert from: https://github.com/FiloSottile/mkcert#installation"
  exit 1
fi

echo "${BLUE}Switching to HTTPS mode with mkcert...${RESET}"

sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^TLS_PROVIDER=.*/TLS_PROVIDER="self-managed"/' .env && rm -f .env.bak

set_https "true"
set_letsencrypt_config "false"

# For some commands we must invoke a Windows executable if in the context of
# WSL.
IS_WSL=$(grep -q WSL /proc/version 2>/dev/null && echo "true" || echo "false")
readonly IS_WSL
if [[ "${IS_WSL}" == "true" ]]; then
  MKCERT=mkcert.exe
else
  MKCERT=mkcert
fi
readonly MKCERT

if [[ "${IS_WSL}" == "true" ]]; then
  CAROOT=$("${MKCERT}" -CAROOT | xargs -0 wslpath -u)
else
  CAROOT=$("${MKCERT}" -CAROOT)
fi
readonly CAROOT

"${MKCERT}" -install || sudo "${MKCERT}" -install

PROGDIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
readonly PROGDIR

if [ ! -f "${PROGDIR}/certs/rootCA-key.pem" ]; then
  cp "${CAROOT}/rootCA-key.pem" "${PROGDIR}/certs/rootCA-key.pem"
fi

if [ ! -f "${PROGDIR}/certs/rootCA.pem" ]; then
  cp "${CAROOT}/rootCA.pem" "${PROGDIR}/certs/rootCA.pem"
fi

"${MKCERT}" -cert-file certs/cert.pem -key-file certs/privkey.pem \
  "*.islandora.io" \
  "islandora.io" \
  "*.islandora.info" \
  "islandora.info" \
  "*.islandora.traefik.me" \
  "islandora.traefik.me" \
  "localhost" \
  "127.0.0.1" \
  "::1"

echo "Done! HTTPS mode enabled with mkcert certificates."
echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
