#!/usr/bin/env bash

set -euo pipefail

project_directory="${GITHUB_WORKSPACE}/.isle-site-template"
module_directory=
if [ -n "$MODULE_OWNER" ]; then
  module_directory="${GITHUB_WORKSPACE}/.drupal-module-under-test"
fi

if [ "$RUNNER_OS" = "Windows" ]; then
  project_source=$project_directory
  # Keep the leaf name aligned with the configured Compose project name.
  project_parent=$(mktemp --directory --tmpdir=/var/tmp isle-ci.XXXXXX)
  project_directory="${project_parent}/isle-site-template"
  mkdir "$project_directory"
  cp -a "${project_source}/." "${project_directory}/"

  if [ -n "$module_directory" ]; then
    module_source=$module_directory
    module_directory="${project_parent}/drupal-module-under-test"
    mkdir "$module_directory"
    cp -a "${module_source}/." "${module_directory}/"
  fi
fi

{
  echo "project-directory=${project_directory}"
  echo "context-name=${SITECTL_CONTEXT}"
  echo "compose-project-name=isle-site-template"
  echo "drupal-module-directory=${module_directory}"
} >> "$GITHUB_OUTPUT"
