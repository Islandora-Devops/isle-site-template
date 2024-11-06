#!/usr/bin/env bash

COUNTER=0
while true; do
  HTTP_STATUS=$(curl -w '%{http_code}' -o /dev/null -s https://islandora.dev/)
  echo "Ping returned http status ${HTTP_STATUS}, exit code $?"
  if [ "${HTTP_STATUS}" -eq 200 ] || [ "${HTTP_STATUS}" -eq 302 ]; then
    echo "We're live 🚀"
    exit 0
  fi

  ((COUNTER++))
  if [ "${COUNTER}" -eq 25 ]; then
    docker compose --profile dev restart drupal-dev
  fi
  if [ "${COUNTER}" -eq 50 ]; then
    echo "Failed to come online after 4m"
    exit 1
  fi
  sleep 5;
done
