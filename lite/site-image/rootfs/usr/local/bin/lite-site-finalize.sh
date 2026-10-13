#!/command/with-contenv bash
# shellcheck shell=bash
#
# Localize a production database for this stack. Runs inside drupal-<site>, once at first
# start (from install.sh) and again on demand (`make site-finalize SITE=<site>`; before the
# first start finished only with FORCE=1). The order matters and follows the menus
# runbook: services must be re-pointed and the Solr core must exist BEFORE updb, because
# the views post-updates re-save facets and need a reachable Search API server.
set -euo pipefail

# shellcheck disable=SC1091
source /etc/islandora/utilities.sh

readonly SITE="default"
readonly URI="${DRUSH_OPTIONS_URI}"
readonly CORE="${DRUPAL_DEFAULT_SOLR_CORE:-default}"
readonly SOLR="http://${DRUPAL_DEFAULT_SOLR_HOST:-solr}:${DRUPAL_DEFAULT_SOLR_PORT:-8983}"
readonly MODE="${LITE_PLACEHOLDERS:-relink}"

cd /var/www/drupal
d() { drush --root=/var/www/drupal --uri="${URI}" -y "$@"; }

if [ ! -f /installed ] && [ -z "${FORCE:-}" ] && [ -n "${LITE_FINALIZE_MANUAL:-}" ]; then
  echo "First start has not completed yet; wait for 'Install Completed' or run with FORCE=1." >&2
  exit 1
fi

echo "== 1 database: content; accounts replaced by the Lite dev site's (never production credentials)"
d sql:query 'SELECT COUNT(*) AS nodes FROM node_field_data' || true
if [ "${LITE_ACCOUNTS:-lite}" = "lite" ]; then
  lite-accounts-from-lite.sh || echo "WARN: could not copy accounts from the Lite site; run make site-users-from-lite SITE=<site>"
fi

echo "== 2 point services at this stack (Solr, IIIF, FITS, Mirador, advancedqueue, ffmpeg)"
lite-hydrate.sh
if d pm:list --status=enabled --format=list 2>/dev/null | grep -qx search_api_solr; then
  repointed=0
  for server in $(d php:eval 'print implode(PHP_EOL, \Drupal::configFactory()->listAll("search_api.server."));' 2>/dev/null || true); do
    backend="$(d config:get "${server}" backend --format=string 2>/dev/null || true)"
    case "${backend}" in *search_api_solr*) ;; *) continue ;; esac
    host="$(d config:get "${server}" backend_config.connector_config.host --format=string --include-overridden 2>/dev/null || true)"
    echo "   ${server}: host=${host}"
    [ "${host}" = "${DRUPAL_DEFAULT_SOLR_HOST:-solr}" ] && repointed=$((repointed + 1))
  done
  if [ "${repointed}" -eq 0 ]; then
    echo "ERROR: search_api_solr is enabled but no Solr server points at ${DRUPAL_DEFAULT_SOLR_HOST:-solr}; updb would abort on facets." >&2
    exit 1
  fi
fi

echo "== 3 JWT key"
configure_jwt_module "${SITE}" || true

echo "== 4 Solr core '${CORE}'"
if curl -fsS "${SOLR}/solr/admin/cores?action=STATUS&core=${CORE}&wt=json" | jq -e --arg c "${CORE}" '.status[$c] != null and (.status[$c] | length > 0)' >/dev/null 2>&1; then
  echo "   core ${CORE} already exists (shared core), left as is"
  [ -d /opt/lite/solr/conf ] && echo "   (make site-solr-conf SITE=<site> replaces its config with this site's solr/conf)"
elif [ -d /opt/lite/solr/conf ]; then
  # The site's production Solr config (lite/sites/<site>/solr/conf, adapted by intake).
  lite-solr-conf.sh || echo "WARN: Solr core not created, see above"
else
  create_solr_core_with_default_config "${SITE}" || echo "WARN: Solr core not created, see above"
  # The search_api_solr config.zip carries a core.properties that lands in <core>/conf/;
  # Solr would register it as a phantom core named "conf" on its next start.
  rm -f "/opt/solr/server/solr/${CORE}/conf/core.properties"
fi

echo "== 5 remove facets whose index field no longer exists (prod leftovers abort the views post-updates)"
if d pm:list --status=enabled --format=list 2>/dev/null | grep -qx facets; then
  d php:script /opt/lite/scripts/delete-orphan-facets.php || true
fi

echo "== 6 schema updates (prod data may be older than this codebase); no config import"
d updb --no-cache-clear
d cache:rebuild
d search-api:reset-tracker || true

if grep -qE '^[[:space:]]+triplestore_indexer:[[:space:]]*0' /var/www/drupal/config/sync/core.extension.yml 2>/dev/null; then
  echo "== 7 Blazegraph namespace '${DRUPAL_DEFAULT_TRIPLESTORE_NAMESPACE}'"
  create_blazegraph_namespace_with_default_properties "${SITE}" || echo "WARN: namespace not created"
fi

echo "== 8 uid 1 password = secret DRUPAL_DEFAULT_ACCOUNT_PASSWORD (accounts are the Lite site's)"
if [ -s /run/secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD ]; then
  # sql:query prints a trailing blank line: take the last non-empty one.
  uid1="$(d sql:query 'SELECT name FROM users_field_data WHERE uid = 1' 2>/dev/null | awk 'NF {v=$0} END {print v}' || true)"
  if [ -n "${uid1}" ]; then
    d user:password "${uid1}" "$(cat /run/secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD)" && echo "   uid 1 is '${uid1}'; password set to secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD"
    d user:unblock "${uid1}" >/dev/null 2>&1 || true
    d user:role:add administrator "${uid1}" >/dev/null 2>&1 || true
  else
    echo "WARN: no uid 1 account (run make site-users-from-lite SITE=<site>)"
  fi
fi

echo "== 9 site files named in config (logo, ...), copied only when missing"
( cd /opt/lite/site-files 2>/dev/null && find . -type f ! -name .gitkeep | while read -r f; do
    dest="/var/www/drupal/web/sites/default/files/${f#./}"
    [ -e "${dest}" ] || { mkdir -p "$(dirname "${dest}")" && cp "${f}" "${dest}" && chown nginx:nginx "${dest}" && echo "   copied ${f#./}"; }
  done ) || true

echo "== 10 media placeholders (mode: ${MODE}); files are never part of a handover"
case "${MODE}" in
  relink)   d php:script /opt/lite/scripts/relink-media-placeholders.php ;;
  per-file) d php:script /opt/lite/scripts/make-placeholder-files.php ;;
  false|no|off|"") echo "   skipped (make site-placeholders SITE=<site> later)" ;;
  *) echo "WARN: unknown LITE_PLACEHOLDERS='${MODE}', skipped" ;;
esac
case "${MODE}" in
  relink|per-file)
    echo "   files referenced by config and text fields (theme logo, inline images) that are not managed files:"
    d php:script /opt/lite/scripts/ensure-referenced-files.php ;;
esac
d cache:rebuild   # drop cached 404s for files that did not exist a moment ago

if [ -n "${LITE_PROD_DOMAIN:-}" ]; then
  echo "== 11 config objects still mentioning the production domain (${LITE_PROD_DOMAIN}); review by hand:"
  d sql:query "SELECT name FROM config WHERE data REGEXP '${LITE_PROD_DOMAIN}'" | sed 's/^/     /' || true
fi

chown -R nginx:nginx /var/www/drupal/web/sites/default /var/www/drupal/private
d state:set lite.localized "$(date -u +%FT%TZ)"
d status --fields=drupal-version,db-status,theme,uri
echo "Next: make site-drush SITE=<site> CMD=\"search-api:index\"   (reindex, when you want)"
d uli || true
