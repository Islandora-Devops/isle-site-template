#!/usr/bin/env bash

set -euo pipefail

create_args=(
  create isle/default
  --path "$PROJECT_DIRECTORY"
  --type local
  --checkout-source existing
  --context "$SITECTL_CONTEXT"
  --site islandora
  --environment local
  --project-name isle-site-template
  --compose-project-name isle-site-template
  --default-context
  --yolo
  --fcrepo on
  --isle-file-system-uri private
  --blazegraph on
  --iiif cantaloupe
  --iiif-topology disabled
  --codebase nested
  --fits on
  --crayfits on
  --homarus on
  --houdini on
  --hypercube on
  --mergepdf on
  --ingress on
  --mode http
  --domain islandora.io
  --max-upload-size 128M
  --upload-timeout 300s
  --bot-mitigation off
  --dev-mode off
  --image "activemq=islandora/activemq:${BUILDKIT_TAG}"
  --image "alpaca=islandora/alpaca:${BUILDKIT_TAG}"
  --image "blazegraph=islandora/blazegraph:${BUILDKIT_TAG}"
  --image "cantaloupe=islandora/cantaloupe:${BUILDKIT_TAG}"
  --image "crayfits=islandora/crayfits:${BUILDKIT_TAG}"
  --image "fcrepo=islandora/fcrepo6:${BUILDKIT_TAG}"
  --image "fits=islandora/fits:${BUILDKIT_TAG}"
  --image "homarus=islandora/homarus:${BUILDKIT_TAG}"
  --image "houdini=islandora/houdini:${BUILDKIT_TAG}"
  --image "hypercube=islandora/hypercube:${BUILDKIT_TAG}"
  --image "init=islandora/base:${BUILDKIT_TAG}"
  --image "mariadb=islandora/mariadb:${BUILDKIT_TAG}"
  --image "mergepdf=islandora/mergepdf:${BUILDKIT_TAG}"
  --image "milliner=islandora/milliner:${BUILDKIT_TAG}"
  --image "solr=islandora/solr:${BUILDKIT_TAG}"
  --build-arg drupal.REPOSITORY=islandora
  --build-arg "drupal.TAG=${BUILDKIT_TAG}"
)

sitectl "${create_args[@]}"
sitectl healthcheck \
  --context "$SITECTL_CONTEXT" \
  --persist \
  --timeout "$HEALTHCHECK_TIMEOUT" \
  --interval "$HEALTHCHECK_INTERVAL" \
  --format table
