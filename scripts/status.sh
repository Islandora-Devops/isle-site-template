#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

echo_e "${BLUE}--- General Status ---${RESET}"

if is_dev_mode; then
    echo_e "Site mode: ${GREEN}Development${RESET}"
elif is_prod_mode; then
    echo_e "Site mode: ${GREEN}Production${RESET}"
else
    echo_e "Site mode: ${RED}Unknown${RESET} (DEVELOPMENT_ENVIRONMENT is not set to 'true' or 'false' in .env)"
fi

echo_e "COMPOSE_PROJECT_NAME: ${GREEN}${COMPOSE_PROJECT_NAME}${RESET}"
if [ "$ISLANDORA_TAG" = "unknown" ]; then
  if grep -q "\${ISLANDORA_TAG}" docker-compose.yml; then
    echo_e "ISLANDORA_TAG: ${RED}${ISLANDORA_TAG}${RESET}"
    echo -e "\tYou need to set ISLANDORA_TAG in .env"
  fi
else
  echo_e "ISLANDORA_TAG: ${GREEN}${ISLANDORA_TAG}${RESET}"
fi


if is_dev_mode && is_docker_rootless; then
    print_warning_header
    echo_e "\t${RED}Docker Security: rootless${RESET}"
    echo_e "\tYou appear to be running docker in rootless mode."
    echo_e "\tYou must set DEVELOPMENT_ENVIRONMENT=false in .env\n"
fi

# --- Docker Override Check ---
if is_dev_mode && has_no_docker_override; then
    print_warning_header
    echo_e "\t${YELLOW}Mount drupal codebase into drupal container for local development${RESET}"
    echo -e "\tFor easier local development, you can link the sample docker-compose override file."
    echo -e "\tThis allows you to mount your local Drupal codebase into the container."
    echo -e "\tTo do so you can run the following command:"
    echo_e "\t${BLUE}ln -s docker-compose.dev.yml docker-compose.override.yml${RESET}"
    echo_e "\tAnd then run ${BLUE}make up${RESET} for the changes to apply.\n"
fi


if [ "${COMPOSE_PROJECT_NAME}" = "isle-site-template" ]; then
    print_warning_header
    echo_e "\t${YELLOW}Update COMPOSE_PROJECT_NAME in .env${RESET}"
    echo -e "\tDocker Compose uses this name to prefix containers, networks, and volumes."
    echo -e "\tRunning multiple projects with the same name on one machine will cause conflicts."
    echo -e "\tThis is mostly relevant for development environments that may have multiple ISLE sites"
    echo -e "\tBut may also be a concern is a single host serves multiple ISLE sites."
    echo -e "\tEnsure this value is unique if you run other Docker Compose projects.\n"
fi

if [ ! -f secrets/JWT_PRIVATE_KEY ]; then
    print_warning_header
    echo_e "\t${RED}Missing JWT Private Key${RESET}: secrets/JWT_PRIVATE_KEY not found"
    echo -e "\tGenerate JWT keys for authentication to work properly.\n"
elif [ ! -f secrets/JWT_PUBLIC_KEY ]; then
    print_warning_header
    echo_e "\t${RED}Missing JWT Public Key${RESET}: secrets/JWT_PUBLIC_KEY not found"
    echo -e "\tGenerate JWT keys for authentication to work properly.\n"
elif command -v openssl &> /dev/null; then
    EXTRACTED_PUBLIC=$(openssl rsa -in secrets/JWT_PRIVATE_KEY -pubout 2>/dev/null || echo "EXTRACT_FAILED")
    STORED_PUBLIC=$(cat secrets/JWT_PUBLIC_KEY 2>/dev/null || echo "READ_FAILED")

    if [ "$EXTRACTED_PUBLIC" = "EXTRACT_FAILED" ]; then
        print_warning_header
        echo_e "\t${RED}Invalid JWT Private Key${RESET}: Cannot read secrets/JWT_PRIVATE_KEY"
        echo_e "\tThe private key file may be corrupted or in wrong format.\n"
    elif [ "$STORED_PUBLIC" = "READ_FAILED" ]; then
        print_warning_header
        echo_e "\t${RED}Cannot Read JWT Public Key${RESET}: Failed to read secrets/JWT_PUBLIC_KEY\n"
    elif [ "$EXTRACTED_PUBLIC" != "$STORED_PUBLIC" ]; then
        print_warning_header
        echo_e "\t${RED}JWT Key Mismatch${RESET}: Public and private keys do not match"
        echo_e "\tThe public key in secrets/JWT_PUBLIC_KEY does not correspond to the private key."
        echo_e "\tRegenerate both keys or ensure they are a matching pair.\n"
    else
        echo_e "JWT key pair: ${GREEN}Valid${RESET}: secrets/JWT_PUBLIC_KEY and secrets/JWT_PRIVATE_KEY match\n"
    fi
fi

./scripts/status-traefik.sh
