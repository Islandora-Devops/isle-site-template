#!/usr/bin/env bash

set -euo pipefail

if { [ "$RUNNER_OS" != "Linux" ] && [ "$RUNNER_OS" != "Windows" ]; } || \
  [ "$RUNNER_ARCH" != "X64" ]; then
  echo "::error::Setup ISLE supports Linux or Windows X64 runners."
  exit 1
fi

regex_docker='^[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}$'
regex_owner='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$'
regex_repository='^[a-zA-Z0-9._-]{1,100}$'
regex_context='^[a-zA-Z0-9][a-zA-Z0-9._-]*$'
regex_duration='^[0-9]+(ms|s|m|h)$'

validate() {
  local name=$1
  local value=$2
  local regex=$3
  if [[ ! $value =~ $regex ]]; then
    echo "::error::Invalid ${name} input."
    exit 1
  fi
}

validate_ref() {
  local name=$1
  local value=$2
  if ! git check-ref-format --branch "$value" >/dev/null 2>&1; then
    echo "::error::Invalid ${name} input."
    exit 1
  fi
}

validate "buildkit-tag" "$BUILDKIT_TAG" "$regex_docker"
validate "isle-site-template-owner" "$TEMPLATE_OWNER" "$regex_owner"
validate "isle-site-template-repository" "$TEMPLATE_REPOSITORY" "$regex_repository"
validate_ref "isle-site-template-ref" "$TEMPLATE_REF"
validate "starter-site-owner" "$STARTER_OWNER" "$regex_owner"
validate "starter-site-repository" "$STARTER_REPOSITORY" "$regex_repository"
validate_ref "starter-site-ref" "$STARTER_REF"
validate "context-name" "$SITECTL_CONTEXT" "$regex_context"
validate "healthcheck-timeout" "$HEALTHCHECK_TIMEOUT" "$regex_duration"
validate "healthcheck-interval" "$HEALTHCHECK_INTERVAL" "$regex_duration"

module_inputs=0
[ -n "$MODULE_OWNER" ] && module_inputs=$((module_inputs + 1))
[ -n "$MODULE_REPOSITORY" ] && module_inputs=$((module_inputs + 1))
[ -n "$MODULE_REF" ] && module_inputs=$((module_inputs + 1))
if [ "$module_inputs" -ne 0 ] && [ "$module_inputs" -ne 3 ]; then
  echo "::error::Drupal module owner, repository, and ref must be supplied together."
  exit 1
fi
if [ "$module_inputs" -eq 3 ]; then
  validate "drupal-module-owner" "$MODULE_OWNER" "$regex_owner"
  validate "drupal-module-repository" "$MODULE_REPOSITORY" "$regex_repository"
  validate_ref "drupal-module-ref" "$MODULE_REF"
fi
