#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/profile.sh"

# 1. Load Environment Variables
if [ -f .env ]; then
  # Export variables so docker-compose and this script can see them
  # shellcheck disable=SC1091
  source .env
else
  echo "Error: .env file not found." >&2
  exit 1
fi

# 2. Set Defaults
HTTP_PORT=80
HTTPS_PORT=443

# 3. Resolve Ports
HOST_INSECURE_PORT=$(find_port $HTTP_PORT "HTTP")
HOST_SECURE_PORT=$(find_port $HTTPS_PORT "HTTPS")
export HOST_INSECURE_PORT HOST_SECURE_PORT

# 4. Start Docker Compose
docker compose up --remove-orphans -d

# 5. Determine URL and Port
if [ "$ENABLE_HTTPS" = "true" ]; then
    PROTOCOL="https"
    FINAL_PORT="$HOST_SECURE_PORT"
    DEFAULT_P=443
else
    PROTOCOL="http"
    FINAL_PORT="$HOST_INSECURE_PORT"
    DEFAULT_P=80
fi

# Build the URL
URL="$PROTOCOL://$DOMAIN"
if [ "$FINAL_PORT" != "$DEFAULT_P" ]; then
    URL="$URL:$FINAL_PORT"
fi

echo "---------------------------------------------------"
echo "🚀 Site starting at: $URL"
echo "---------------------------------------------------"

# don't open the URL if we're in GHA
if [ "${GITHUB_ACTIONS:-}" != "" ]; then
  exit 0
fi

# don't open the URL if we're in an SSH session
if [ -n "${SSH_CONNECTION:-}" ] || [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ]; then
  exit 0
fi

sleep 10

# 6. Open in Browser (Cross-Platform)
case "$(uname -s)" in
    Darwin*)    open "$URL" ;;
    Linux*)     if grep -qi microsoft /proc/version; then
                    powershell.exe Start-Process "$URL" # WSL
                else
                    xdg-open "$URL" # Standard Linux
                fi ;;
    CYGWIN*|MINGW*|MSYS*) start "$URL" ;; # Windows Native
    *)          echo "Please open $URL in your browser." ;;
esac

