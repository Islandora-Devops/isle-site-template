#!/command/with-contenv bash
# shellcheck shell=bash
#
# Install this site's production Solr config for its core. Runs inside drupal-<site>, which
# mounts the core directory (volume solr-core-<core>) at the same path as the solr service.
# The config is the operator's lite/sites/<site>/solr/conf, adapted to this stack's Solr and
# test-loaded by `make site-intake` (lite/intake/solr-conf.sh), baked in at /opt/lite/solr/conf.
#
#   lite-solr-conf.sh            core absent: create it from /opt/lite/solr/conf
#                                core present: leave it as is
#   lite-solr-conf.sh --replace  core present: swap its conf/ for this site's and RELOAD (the
#                                old conf/ is kept as conf.bak-<timestamp>; a failed RELOAD
#                                restores it). `make site-solr-conf SITE=<site>`
#
# Exit 2 when the site has no Solr config (the caller generates one instead).
set -euo pipefail

# shellcheck disable=SC1091
source /etc/islandora/utilities.sh

readonly SITE="default"
readonly CORE="${DRUPAL_DEFAULT_SOLR_CORE:-default}"
readonly SOLR="http://${DRUPAL_DEFAULT_SOLR_HOST:-solr}:${DRUPAL_DEFAULT_SOLR_PORT:-8983}"
readonly SRC="/opt/lite/solr/conf"
readonly DEST="/opt/solr/server/solr/${CORE}"

replace=0
[ "${1:-}" = "--replace" ] && replace=1

if [ ! -d "${SRC}" ]; then
  echo "No Solr config in this image (${SRC}): put the production conf/ folder in lite/sites/<site>/solr/conf," >&2
  echo "then make site-intake, site-build and site-up for the site." >&2
  exit 2
fi

core_exists() {
  curl -fsS "${SOLR}/solr/admin/cores?action=STATUS&core=${CORE}&indexInfo=false&wt=json" |
    jq -e --arg c "${CORE}" '.status[$c] != null and (.status[$c] | length > 0)' >/dev/null 2>&1
}

reload() {
  curl -fsS "${SOLR}/solr/admin/cores?action=RELOAD&core=${CORE}&wt=json" >/dev/null
}

install_conf() {
  mkdir -p "${DEST}/conf" "${DEST}/data"
  cp -R "${SRC}/." "${DEST}/conf/"
  # The uid:gid "100:1000" is "solr:solr" inside of the solr container (as in generate_solr_config).
  chown -R 100:1000 "${DEST}"
}

wait_for_service "${SITE}" solr

if ! core_exists; then
  echo "Creating Solr core '${CORE}' from ${SRC}"
  install_conf
  create_solr_core "${SITE}"
  core_exists || { echo "ERROR: Solr core '${CORE}' was not created, see the Solr log." >&2; exit 1; }
  exit 0
fi

if [ "${replace}" -eq 0 ]; then
  echo "Solr core '${CORE}' already exists, left as is (replace its config with --replace)."
  exit 0
fi

backup="${DEST}/conf.bak-$(date +%Y%m%d%H%M%S)"
echo "Replacing the config of Solr core '${CORE}' (previous config: ${backup})"
mv "${DEST}/conf" "${backup}"
install_conf
if reload; then
  echo "Reloaded Solr core '${CORE}'."
else
  echo "ERROR: RELOAD failed with the site's config; restoring ${backup}." >&2
  rm -rf "${DEST}/conf"
  mv "${backup}" "${DEST}/conf"
  reload || echo "ERROR: RELOAD with the restored config failed too, check the Solr log." >&2
  exit 1
fi
