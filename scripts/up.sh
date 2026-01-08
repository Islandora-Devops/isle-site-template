#!/usr/bin/env bash

set -eou pipefail

if [ -f .env ]; then
  # Export variables so docker-compose and this script can see them
  # shellcheck disable=SC1091
  source .env
else
  echo "Error: .env file not found." >&2
  ./scripts/init.sh
  source .env
fi

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

HTTP_PORT=80
HTTPS_PORT=443

HOST_INSECURE_PORT=$(find_port $HTTP_PORT "HTTP")
HOST_SECURE_PORT=$(find_port $HTTPS_PORT "HTTPS")
export HOST_INSECURE_PORT HOST_SECURE_PORT

docker compose up --remove-orphans -d

if [ "$URI_SCHEME" = "https" ]; then
    PROTOCOL="https"
    FINAL_PORT="$HOST_SECURE_PORT"
    DEFAULT_P=443
else
    PROTOCOL="http"
    FINAL_PORT="$HOST_INSECURE_PORT"
    DEFAULT_P=80
fi

URL="$PROTOCOL://$DOMAIN"
if [ "$FINAL_PORT" != "$DEFAULT_P" ]; then
    URL="$URL:$FINAL_PORT"
fi

echo "Waiting for installation..."
docker compose logs -f drupal 2>&1 | { \
    while read -r line; do \
        echo "$line"; \
        if echo "$line" | grep -q "Install Completed"; then \
            pkill -f "docker compose logs -f drupal" || true; \
            exit 0; \
        fi; \
    done; \
} || true

echo "---------------------------------------------------"
echo "🚀 Site available at: $URL"
echo "---------------------------------------------------"

# don't open the URL if we're in GHA
if [ "${GITHUB_ACTIONS:-}" != "" ]; then
  exit 0
fi

# don't open the URL if we're in an SSH session
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  exit 0
fi

# 6. Open in Browser (Cross-Platform)
case "$(uname -s)" in
    Darwin*)    open "$URL" ;;
    Linux*)     if grep -qi microsoft /proc/version; then
                    powershell.exe Start-Process "$URL" # WSL
                else
                    xdg-open "$URL" # Standard Linux
                fi ;;
    CYGWIN*|MINGW*|MSYS*) start "$URL" ;; # Windows Native
    *)          echo "You can open $URL in your browser." ;;
esac
