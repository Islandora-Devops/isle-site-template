#!/usr/bin/env bash
#
# Intake of a production-site handover for isle-site-lite. Called by `make site-intake
# SITE=<site>` (lite/bin/lite-site intake). Everything is read from lite/sites/<site>/:
#
#   site.env                 settings (SITE_CODE_DIR, SITE_THEMES, SKIP_TABLES, ...)
#   $SITE_CODE_DIR           the site's Drupal composer project (you clone it; default repo/)
#   themes/<name>/           each theme named in SITE_THEMES (you pull them)
#   db/                      the database handover: a mysqldump (*.sql, *.sql.gz, *.sql.xz)
#                            or a .tar.gz / .tgz of raw MySQL 8.0 .ibd files
#   solr/conf/               optional: the production Solr core's conf/ folder (you copy it)
#   lite/cantaloupe/conf/    optional, for the whole stack: production's cantaloupe.properties
#                            and delegate script (you copy them)
#
# Output:
#   stage/                   config/sync, web/themes/<name>, web/modules/custom (COPYd into the image);
#                            solr/conf adapted to this stack's Solr (solr-conf.sh; the image moves it
#                            to /opt/lite/solr/conf)
#   lite/cantaloupe/stage/   cantaloupe.env + delegates.rb for the shared cantaloupe service
#                            (cantaloupe-conf.sh); applied by make site-up / lite-cantaloupe
#   db/<site>.sql.xz         normalized dump, the only thing db-<site> loads; raw inputs move to db/incoming/
#   NOTES.md                 assess report appended
#
# Idempotent: staging is redone every run (cheap); the normalized dump is reused unless
# FORCE=1. This script never clones or downloads anything on your behalf.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
HERE="lite/intake"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[36m'; RESET=$'\033[0m'
info()  { echo "${BLUE}==>${RESET} $*"; }
ok()    { echo "${GREEN}ok${RESET}  $*"; }
warn()  { echo "${YELLOW}warn${RESET} $*" >&2; }
die()   { echo "${RED}error${RESET} $*" >&2; exit 1; }

site="${1:-}"; [ -n "$site" ] || die "usage: $0 <site>"
SITE_DIR="lite/sites/$site"
[ -f "$SITE_DIR/site.env" ] || die "$SITE_DIR/site.env not found (make site-add SITE=$site)"
[ -f "$SITE_DIR/docker-compose.yml" ] || die "$SITE_DIR/docker-compose.yml not found: make site-render SITE=$site"
set -a
# shellcheck disable=SC1090
. "$SITE_DIR/site.env"
set +a
: "${SITE_CODE_DIR:=$SITE_DIR/repo}"
: "${SITE_THEMES:=}"
: "${SITE_DB_NAME:=$site}"
: "${SKIP_TABLES:=cache_.*|cachetags|sessions|flood|semaphore|queue|batch|watchdog|advancedqueue|users|users_field_data|users_data|user__roles|user__user_picture|shortcut_set_users}"
export SITE_DB_NAME SKIP_TABLES

STAGE="$SITE_DIR/stage"
DB_DIR="$SITE_DIR/db"
INCOMING="$DB_DIR/incoming"
NORMALIZED="$DB_DIR/$site.sql.xz"
NOTES="$SITE_DIR/NOTES.md"

# ---------------------------------------------------------------------------------------
info "[1/7] code: $SITE_CODE_DIR"
CODE="$SITE_CODE_DIR"
if [ ! -f "$CODE/config/sync/core.extension.yml" ]; then
  cat >&2 <<EOF
${RED}The site's composer project is not at $CODE (no config/sync/core.extension.yml).${RESET}
Provide it yourself, for example:
  git clone <internal GitHub URL of the site repo> $SITE_DIR/repo
or point SITE_CODE_DIR in $SITE_DIR/site.env at an existing checkout.
EOF
  exit 1
fi
# Only when $CODE is the top of its own checkout (a copy without .git sits inside this repo).
if [ "$(git -C "$CODE" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$CODE" && pwd -P)" ]; then
  code_commit="$(git -C "$CODE" rev-parse --short HEAD 2>/dev/null || echo 'no commits')"
  code_branch="$(git -C "$CODE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
else
  code_commit='not a git checkout'; code_branch='-'
fi
rm -rf "$STAGE"
mkdir -p "$STAGE/config"
cp -R "$CODE/config/sync" "$STAGE/config/sync"
for d in web/modules/custom web/themes/custom; do
  if [ -d "$CODE/$d" ] && [ -n "$(ls -A "$CODE/$d" 2>/dev/null)" ]; then
    mkdir -p "$STAGE/$d"; cp -R "$CODE/$d/." "$STAGE/$d/"
    echo "   staged $d from the site repo"
  fi
done
find "$STAGE" -name .git -prune -exec rm -rf {} + 2>/dev/null || true
ok "staged config/sync ($(ls "$STAGE/config/sync" | wc -l | tr -d ' ') files) from $CODE ($code_branch @ $code_commit)"

# ---------------------------------------------------------------------------------------
info "[2/7] themes: ${SITE_THEMES:-(none listed in SITE_THEMES)}"
mkdir -p "$STAGE/web/themes"
for name in $SITE_THEMES; do
  src="$SITE_DIR/themes/$name"
  if [ ! -d "$src" ]; then
    cat >&2 <<EOF
${RED}Theme '$name' is not at $src.${RESET}
Pull it there yourself (private repo), for example:
  git clone <theme repo URL> $src
or copy an existing checkout to that path.
EOF
    exit 1
  fi
  rm -rf "${STAGE:?}/web/themes/$name"
  cp -R "$src" "$STAGE/web/themes/$name"
  rm -rf "$STAGE/web/themes/$name/.git"
  info_yml="$(find "$STAGE/web/themes/$name" -maxdepth 1 -name '*.info.yml' | head -1)"
  [ -n "$info_yml" ] || die "no *.info.yml at the top of $src; is this a Drupal theme?"
  ok "staged theme $name ($(basename "$info_yml" .info.yml))"
done

# Every theme the config enables must be present: core, contrib shipped by the Lite composer
# set (bootstrap_barrio), or staged here.
known_themes='olivero|claro|stark|stable|stable9|classy|seven|bartik|starterkit_theme|bootstrap_barrio|carapace'
missing_themes=()
wanted="$( { sed -n '/^theme:/,/^[a-z]/p' "$STAGE/config/sync/core.extension.yml" | grep -E '^[[:space:]]+[a-z0-9_]+:' | sed -E 's/^[[:space:]]+([a-z0-9_]+):.*/\1/'; grep -E '^(default|admin):' "$STAGE/config/sync/system.theme.yml" 2>/dev/null | cut -d: -f2 | tr -d ' '; } | sort -u )"
for t in $wanted; do
  echo "$t" | grep -Eqx "$known_themes" && continue
  if ! find "$STAGE/web/themes" -name "$t.info.yml" | grep -q .; then
    missing_themes+=("$t")
  fi
done
if [ "${#missing_themes[@]}" -gt 0 ]; then
  die "config enables theme(s) not provided: ${missing_themes[*]}. Add each to SITE_THEMES in $SITE_DIR/site.env and put the theme under $SITE_DIR/themes/<dir>/ (its <name>.info.yml must be '<theme>.info.yml')."
fi
ok "theme check passed (enabled: $(echo $wanted | tr '\n' ' '))"

# ---------------------------------------------------------------------------------------
info "[3/7] Solr config: $SITE_DIR/solr/conf (optional)"
SOLR_CONF="$SITE_DIR/solr/conf"
if [ -f "$SOLR_CONF/solrconfig.xml" ]; then
  "$HERE/solr-conf.sh" "$SOLR_CONF" "$STAGE/solr/conf"
  solr_source="solr/conf adapted and test-loaded ($(find "$STAGE/solr/conf" -type f | wc -l | tr -d ' ') files)"
  ok "staged the Solr config for core ${SITE_SOLR_CORE:-dsu_multisite}"
else
  solr_source="none (a core this site creates gets the config search_api_solr generates)"
  warn "no $SOLR_CONF/solrconfig.xml: $solr_source"
fi

# ---------------------------------------------------------------------------------------
CANTALOUPE_CONF="lite/cantaloupe/conf"
CANTALOUPE_STAGE="lite/cantaloupe/stage"
info "[4/7] Cantaloupe config: $CANTALOUPE_CONF (optional, shared by the whole stack)"
if [ -f "$CANTALOUPE_CONF/cantaloupe.properties" ]; then
  "$HERE/cantaloupe-conf.sh" "$CANTALOUPE_CONF" "$CANTALOUPE_STAGE"
  cantaloupe_source="$CANTALOUPE_CONF translated and test-started"
  ok "staged the Cantaloupe config in $CANTALOUPE_STAGE (make site-up applies it)"
else
  if [ -f "$CANTALOUPE_STAGE/cantaloupe.env" ]; then
    rm -rf "$CANTALOUPE_STAGE"
    echo "   removed $CANTALOUPE_STAGE (its source is gone); make site-up returns cantaloupe to the image's config"
  fi
  cantaloupe_source="none (the image's config)"
  warn "no $CANTALOUPE_CONF/cantaloupe.properties: cantaloupe keeps the image's config"
fi

# ---------------------------------------------------------------------------------------
info "[5/7] database handover in $DB_DIR"
mkdir -p "$INCOMING"
# Raw inputs must not sit next to the normalized dump: db-<site> loads every *.sql* in db/.
shopt -s nullglob
for f in "$DB_DIR"/*.sql "$DB_DIR"/*.sql.gz "$DB_DIR"/*.sql.xz "$DB_DIR"/*.tar.gz "$DB_DIR"/*.tgz; do
  [ "$f" = "$NORMALIZED" ] && continue
  mv "$f" "$INCOMING/"
  echo "   moved $(basename "$f") to db/incoming/"
done
shopt -u nullglob

if [ -s "$NORMALIZED" ] && [ -z "${FORCE:-}" ]; then
  ok "normalized dump present: $NORMALIZED ($(du -h "$NORMALIZED" | cut -f1)); FORCE=1 to rebuild it"
  db_source="existing $NORMALIZED"
else
  dump="$(ls -t "$INCOMING"/*.sql "$INCOMING"/*.sql.gz "$INCOMING"/*.sql.xz 2>/dev/null | head -1 || true)"
  tarball="$(ls -t "$INCOMING"/*.tar.gz "$INCOMING"/*.tgz 2>/dev/null | head -1 || true)"
  if [ -n "$dump" ]; then
    [ -n "$tarball" ] && warn "both a dump and a tarball found; the dump wins ($(basename "$dump"))"
    info "mysqldump handover: $(basename "$dump")"
    "$HERE/normalize-dump.sh" "$dump" "$NORMALIZED"
    db_source="dump $(basename "$dump")"
  elif [ -n "$tarball" ]; then
    info ".ibd handover: $(basename "$tarball") (recovery through a throwaway mysql:8.0; this takes a while)"
    "$HERE/ibd-recover.sh" "$site" "$tarball" "$NORMALIZED"
    db_source="ibd tarball $(basename "$tarball")"
  else
    cat >&2 <<EOF
${RED}No database handover found in $DB_DIR.${RESET}
Copy the file you were given into that folder:
  a mysqldump file  (*.sql, *.sql.gz, *.sql.xz), or
  an archive of raw MySQL 8.0 .ibd files (*.tar.gz, *.tgz)
then run make site-intake SITE=$site again.
EOF
    exit 1
  fi
  ok "normalized dump: $NORMALIZED ($(du -h "$NORMALIZED" | cut -f1))"
fi

# ---------------------------------------------------------------------------------------
info "[6/7] assess"
report="$("$HERE/assess.sh" "$site" "$CODE" "$STAGE" "$NORMALIZED" 2>&1)" || true
{
  echo
  echo "## Intake $(date +'%F %H:%M')"
  echo
  echo "- code: \`$CODE\` ($code_branch @ $code_commit)"
  echo "- themes: ${SITE_THEMES:-none}"
  echo "- Solr config: $solr_source"
  echo "- Cantaloupe config: $cantaloupe_source"
  echo "- database: $db_source"
  echo
  echo "$report"
} >> "$NOTES"
echo "$report"
ok "report appended to $NOTES"

# ---------------------------------------------------------------------------------------
info "[7/7] next"
cat <<EOF
  make site-build SITE=$site     # image FROM the Lite image + staged config/themes/site-files
  make site-up    SITE=$site     # start db-$site (loads db/$site.sql.xz) and drupal-$site (localizes once)
EOF
