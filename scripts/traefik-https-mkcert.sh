#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

echo "${BLUE}Switching to HTTPS mode with mkcert...${RESET}"

# Update .env file
sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
sed -i.bak 's/^TLS_PROVIDER=.*/TLS_PROVIDER="self-managed"/' .env && rm -f .env.bak
set_https "true"
set_letsencrypt_config "false"


# Set mkcert executable based on environment
if is_wsl; then
  MKCERT=mkcert.exe
else
  MKCERT=mkcert
fi
readonly MKCERT

# Verify mkcert is installed
if ! command -v "${MKCERT}" &> /dev/null; then
  echo "${RED}Error: ${MKCERT} is not installed or not in PATH${RESET}"
  exit 1
fi

# Get CAROOT path
if is_wsl; then
  CAROOT=$("${MKCERT}" -CAROOT 2>/dev/null | tr -d '\r' | xargs -0 wslpath -u 2>/dev/null || echo "")
else
  CAROOT=$("${MKCERT}" -CAROOT 2>/dev/null)
fi
readonly CAROOT

if [[ -z "${CAROOT}" ]]; then
  echo "${YELLOW}Warning: Could not determine CAROOT path${RESET}"
fi

# try installing mkcert CA as unprivileged
if ! timeout 5 "${MKCERT}" -install 2>/dev/null; then
  # if that didn't work, try again as sudo
  if ! is_wsl; then
    sudo "${MKCERT}" -install
  fi
fi

if is_wsl; then
  timeout 30 certutil.exe -user -addstore root "$(wslpath -w "$(mkcert -CAROOT)/rootCA.pem")"
fi

PROGDIR=$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
readonly PROGDIR

mkdir -p "${PROGDIR}/certs"

if [[ -n "${CAROOT}" ]] && [[ -d "${CAROOT}" ]]; then
  if [[ -f "${CAROOT}/rootCA-key.pem" ]] && [[ ! -f "${PROGDIR}/certs/rootCA-key.pem" ]]; then
    cp "${CAROOT}/rootCA-key.pem" "${PROGDIR}/certs/rootCA-key.pem"
    echo "Copied rootCA-key.pem"
  fi
  
  if [[ -f "${CAROOT}/rootCA.pem" ]] && [[ ! -f "${PROGDIR}/certs/rootCA.pem" ]]; then
    cp "${CAROOT}/rootCA.pem" "${PROGDIR}/certs/rootCA.pem"
    echo "Copied rootCA.pem"
  fi
else
  echo "${YELLOW}Warning: Could not copy root CA files from CAROOT${RESET}"
fi

# Generate certificates
echo "Generating certificates..."

# Convert paths for Windows when in WSL
if is_wsl; then
  CERT_FILE=$(wslpath -w "${PROGDIR}/certs/cert.pem")
  KEY_FILE=$(wslpath -w "${PROGDIR}/certs/privkey.pem")
else
  CERT_FILE="${PROGDIR}/certs/cert.pem"
  KEY_FILE="${PROGDIR}/certs/privkey.pem"
fi

"${MKCERT}" -cert-file "${CERT_FILE}" -key-file "${KEY_FILE}" \
  "*.islandora.io" \
  "islandora.io" \
  "*.islandora.info" \
  "islandora.info" \
  "*.islandora.traefik.me" \
  "islandora.traefik.me" \
  "localhost" \
  "127.0.0.1" \
  "::1"

echo ""
echo "${GREEN}Done! HTTPS mode enabled with mkcert certificates.${RESET}"
echo "Site will be available at: ${GREEN}${URI_SCHEME}://${DOMAIN}${RESET}"
echo ""
echo "Run this for the changes to take effect:"
echo "${BLUE}make down-traefik up${RESET}"
