#!/usr/bin/env bash

set -euf -o pipefail

RESET=$(tput sgr0)
RED=$(tput setaf 9)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 6)
YELLOW=$(tput setaf 3)
readonly RESET RED GREEN BLUE YELLOW
# Export color codes for use by sourcing scripts
export RESET RED GREEN BLUE YELLOW

# Alias for echo -e to avoid shellcheck warnings about printf format strings
# shellcheck disable=SC2039,SC3044
echo_e() {
    echo -e "$@"
}

# update .env variables
update_env() {
    local var="$1"
    local val="$2"
    if grep -Eq "^${var}=" .env; then
        sed -i.bak "s/^$var=.*/$var=$val/" .env && rm .env.bak
    else
        echo "${var}=${val}" | tee -a .env
    fi
}

# Function to check if a port is in use
# Works on Linux, macOS, and WSL
is_port_in_use() {
    local port=$1
    # Try ss first (available on most Linux/WSL systems)
    # Use -tln without -H for compatibility, filter with grep
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | grep -q ":${port}\b"
        return $?
    fi
    # Fall back to lsof (available on macOS and some Linux)
    if command -v lsof >/dev/null 2>&1; then
        lsof -PiTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
        return $?
    fi
    # Last resort: try netstat
    if command -v netstat >/dev/null 2>&1; then
        netstat -tln 2>/dev/null | grep -q ":${port}\b"
        return $?
    fi
    # If no tool available, assume port is free
    return 1
}

# Function to find the next available port
# Depends on the COMPOSE_PROJECT_NAME variable being set in the calling script.
find_port() {
    local port=$1
    if [ "${DEVELOPMENT_ENVIRONMENT:-false}" = "false" ]; then
      printf "%s\n" "$port"
      return
    fi

    while true; do
        # Check if anything is listening on TCP at this port
        if ! is_port_in_use "$port"; then
            break # Port is completely free
        fi

        # If port is busy, check if it's our own docker project
        local container_id
        container_id=$(docker ps -q --filter "publish=$port" || true)

        if [ -n "$container_id" ]; then
            local our_project
            our_project=$(docker inspect "$container_id" --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null || echo "")
            if [ "$our_project" = "$COMPOSE_PROJECT_NAME" ]; then
                printf "Port %s is already assigned to this project (%s).\n" "$port" "$COMPOSE_PROJECT_NAME" >&2
                break
            fi
        fi
        echo_e "${RED}Port $port is used by another process.${RESET}" >&2
        if [ "$port" = "80" ]; then
          port=8080
        elif [ "$port" = "443" ]; then
          port=8443
        else
          port=$((port + 1))
        fi

        echo_e "${YELLOW}Trying $port...${RESET}" >&2
    done
    printf "%s\n" "$port"
}


# --- Configuration Warnings ---
WARNINGS_FOUND=false
print_warning_header() {
    if [ "$WARNINGS_FOUND" = "false" ]; then
        echo_e "${RED}--- Configuration Warnings ---${RESET}"
        WARNINGS_FOUND=true
    fi
}

is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null || false
}

export_env() {
    DEVELOPMENT_ENVIRONMENT=$(grep '^DEVELOPMENT_ENVIRONMENT=' .env | cut -d'=' -f2 | tr -d '"' || echo "false")
    TLS_PROVIDER=$(grep '^TLS_PROVIDER=' .env | cut -d'=' -f2 | tr -d '"' || echo "self-managed")
    URI_SCHEME=$(grep '^URI_SCHEME=' .env | cut -d'=' -f2 | tr -d '"' || echo "http")
    ENABLE_ACME="false"
    if [ "${TLS_PROVIDER}" = "letsencrypt" ]; then
        ENABLE_ACME="true"
    fi
    ENABLE_HTTPS="false"
    if [ "${URI_SCHEME}" = "https" ]; then
        ENABLE_HTTPS="true"
    fi

    ACME_EMAIL=$(grep '^ACME_EMAIL=' .env | cut -d'=' -f2 | tr -d '"' || echo "postmaster@example.com")
    DOMAIN=$(grep '^DOMAIN=' .env | cut -d'=' -f2 | tr -d '"' || echo "islandora.traefik.me")
    ISLANDORA_TAG=$(grep '^ISLANDORA_TAG=' .env | cut -d'=' -f2 | tr -d '"' || echo "main")
    TAG=$(grep '^TAG=' .env | cut -d'=' -f2 | tr -d '"' || echo "local")
    REPOSITORY=$(grep '^REPOSITORY=' .env | cut -d'=' -f2 | tr -d '"' || echo "islandora.io")
    COMPOSE_PROJECT_NAME=$(grep '^COMPOSE_PROJECT_NAME=' .env | cut -d'=' -f2 | tr -d '"' || echo "isle-site-template")

    # Export variables for use by sourcing scripts
    export DEVELOPMENT_ENVIRONMENT ENABLE_HTTPS URI_SCHEME ENABLE_ACME ACME_EMAIL DOMAIN ISLANDORA_TAG COMPOSE_PROJECT_NAME TAG REPOSITORY
}

# --- Environment Check ---
if [ -f .env ]; then
  export_env
else
  echo_e "  ${RED}.env file not found. Cannot determine configuration.${RESET}"
  echo "You should cp sample.env to .env"
  exit 1
fi

# --- Configuration Helper Functions ---

# Check if running in non-interactive mode
is_noninteractive() {
    [ "${ISLE_SITE_TEMPLATE_NONINTERACTIVE:-false}" = "true" ]
}

# Check if Docker volumes exist for a given project name
# Returns 0 (true) if at least one expected volume exists, 1 (false) otherwise
check_volumes_exist() {
    local project_name="$1"
    local key_volumes=("drupal-public-files" "mariadb-data" "fcrepo-data")
    for vol in "${key_volumes[@]}"; do
        if docker volume ls -q 2>/dev/null | grep -q "^${project_name}_${vol}$"; then
            return 0
        fi
    done
    return 1
}

# Prompt user for input with a default value
# Usage: result=$(prompt_with_default "prompt message" "default_value")
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local input

    if is_noninteractive; then
        printf "%s" "$default"
        return
    fi

    printf "%s [%s]: " "$prompt" "$default" >&2
    read -r input
    if [ -z "$input" ]; then
        printf "%s" "$default"
    else
        printf "%s" "$input"
    fi
}

# Development mode for testing - set STATUS_DEV=true to force all warnings to show
status_dev() {
    [ "${STATUS_DEV:-false}" = "true" ]
}

is_docker_rootless() {
    status_dev || docker info -f "{{println .SecurityOptions}}" | grep -qi rootless
}

is_dev_mode() {
    status_dev || [ "${DEVELOPMENT_ENVIRONMENT:-}" = "true" ]
}

is_prod_mode() {
    status_dev || [ "${DEVELOPMENT_ENVIRONMENT:-}" = "false" ]
}

is_https_enabled() {
    status_dev || [ "${URI_SCHEME:-}" = "https" ]
}

is_acme_enabled() {
    status_dev || [ "${TLS_PROVIDER:-}" = "letsencrypt" ]
}

is_acme_using_default_email() {
    status_dev || [ "${ACME_EMAIL:-}" = "postmaster@example.com" ]
}

is_tls_http_uri_mismatch() {
    status_dev || { is_https_enabled && [ "${URI_SCHEME:-}" = "http" ]; }
}

is_http_tls_uri_mismatch() {
    status_dev || { ! is_https_enabled && [ "${URI_SCHEME:-}" = "https" ]; }
}

has_no_docker_override() {
    status_dev || { [ ! -f docker-compose.override.yml ] && [ ! -L docker-compose.override.yml ]; }
}

is_using_non_standard_ports() {
    status_dev || [ "${HTTP_PORT:-80}" != "80" ] || [ "${HTTPS_PORT:-443}" != "443" ]
}

# Detect the host port that maps to 80
traefik_port_80() {
    docker compose port traefik 80 | cut -d: -f2
}

# Detect the host port that maps to 443
traefik_port_443() {
    docker compose port traefik 443 | cut -d: -f2
}

# Set HTTPS with sed
set_https() {
  local enable=$1

  if [ "$enable" = "true" ]; then
    sed -i.bak 's/DRUPAL_ENABLE_HTTPS:.*/DRUPAL_ENABLE_HTTPS: "true"/' docker-compose.yml && rm -f docker-compose.yml.bak
  else
    sed -i.bak 's/DRUPAL_ENABLE_HTTPS:.*/DRUPAL_ENABLE_HTTPS: "false"/' docker-compose.yml && rm -f docker-compose.yml.bak
  fi
}

# Function to set Let's Encrypt config
set_letsencrypt_config() {
  local enable=$1

  update_env TLS_PROVIDER "self-managed"
  sed -i.bak '/--certificatesresolvers.letsencrypt.acme/d' docker-compose.yml && rm -f docker-compose.yml.bak
  sed -i.bak '/--entrypoints.https.http.tls.certResolver/d' docker-compose.yml && rm -f docker-compose.yml.bak

  if [ "$enable" = "true" ]; then
    update_env TLS_PROVIDER "letsencrypt"
    update_env URI_SCHEME "https"

    # shellcheck disable=SC2016
    sed -i.bak '/command: >-/a\
      --entrypoints.https.http.tls.certResolver=letsencrypt\
      --certificatesresolvers.letsencrypt.acme.httpchallenge=true\
      --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http\
      --certificatesresolvers.letsencrypt.acme.storage=/acme/acme.json\
      --certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}\
      --certificatesresolvers.letsencrypt.acme.caserver=${ACME_URL}
' docker-compose.yml && rm -f docker-compose.yml.bak
  fi
}

# Get the IP a hostname resolves to
get_dns_ip() {
  local hostname="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short "$hostname" 2>/dev/null | head -1
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$hostname" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -1
  elif command -v host >/dev/null 2>&1; then
    host "$hostname" 2>/dev/null | awk '/has address/ { print $4 }' | head -1
  else
    echo ""
  fi
}
