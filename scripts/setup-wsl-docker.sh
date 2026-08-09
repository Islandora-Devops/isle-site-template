#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends \
  ca-certificates \
  curl \
  docker-buildx \
  docker-compose-v2 \
  docker.io \
  git \
  sudo \
  tar

daemon_log="${RUNNER_TEMP}/isle-dockerd.log"
if ! docker info >/dev/null 2>&1; then
  service docker start || true
fi
if ! docker info >/dev/null 2>&1; then
  nohup dockerd >"$daemon_log" 2>&1 </dev/null &
fi

docker_ready=false
for _ in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    docker_ready=true
    break
  fi
  sleep 2
done
if [ "$docker_ready" != true ]; then
  service docker status || true
  [ ! -f "$daemon_log" ] || tail -200 "$daemon_log"
  echo "::error::Docker did not start inside WSL."
  exit 1
fi
docker buildx version
docker compose version
