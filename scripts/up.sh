#!/usr/bin/env bash

set -eou pipefail

# 1. Load Environment Variables
if [ -f .env ]; then
  # Export variables so docker-compose and this script can see them
  # shellcheck disable=SC1091
  source .env
else
  echo "Error: .env file not found."
  exit 1
fi

# 2. Set Defaults
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
HTTP_PORT=80
HTTPS_PORT=443

# Function to find the next available port
find_port() {
    local port=$1
    while true; do
        # Check if anything is listening on TCP at this port
        local pids
        pids=$(lsof -PiTCP:"$port" -sTCP:LISTEN -t 2>/dev/null || true)
        
        if [ -z "$pids" ]; then
            break # Port is completely free
        fi
        
        # If port is busy, check if it's our own docker project
        local container_id
        container_id=$(docker ps -q --filter "publish=$port" || true)
        
        if [ -n "$container_id" ]; then
            local our_project
            our_project=$(docker inspect "$container_id" --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null || echo "")
            if [ "$our_project" = "$PROJECT_NAME" ]; then
                echo "Port $port is already assigned to this project ($PROJECT_NAME)." >&2
                break
            fi
        fi
        
        echo "Port $port is used by another process. Trying $((port + 1))..." >&2
        port=$((port + 1))
    done
    echo "$port"
}

# 3. Resolve Ports
HOST_INSECURE_PORT=$(find_port $HTTP_PORT "HTTP")
HOST_SECURE_PORT=$(find_port $HTTPS_PORT "HTTPS")
export HOST_INSECURE_PORT HOST_SECURE_PORT

# 4. Start Docker Compose
docker compose up --remove-orphans -d

# 5. Determine URL and Port
if [ "$ENABLE_HTTPS" = "true" ]; then
    PROTOCOL="https"
    FINAL_PORT=$HOST_SECURE_PORT
    DEFAULT_P=443
else
    PROTOCOL="http"
    FINAL_PORT=$HOST_INSECURE_PORT
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

# don't open the URL is we're in GHA
if [ "${GITHUB_ACTIONS:-}" != "" ]; then
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

