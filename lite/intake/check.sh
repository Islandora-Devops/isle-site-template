#!/usr/bin/env bash
#
# Validate the manual inputs of a production-site replica before intake. Called by
# `make site-check SITE=<site>` (lite/bin/lite-site check) and at the start of
# `make site-intake`. Read-only: nothing is moved, staged or converted. Every problem is
# reported (not only the first); exits 1 if any is an error.
#
#   site.env                 SITE_THEMES are directory names, values well-formed
#   $SITE_CODE_DIR           the site's composer project with config/sync
#   themes/<name>/           each SITE_THEMES entry is a theme folder; every theme the config
#                            enables is provided
#   db/, db/incoming/        a database handover (or an existing normalized dump) that looks
#                            like what its name says
#   solr/conf/               optional: the production Solr core's conf/ folder
#   lite/cantaloupe/conf/    optional, for the whole stack: production's Cantaloupe config
#   host                     docker and the stack's .env (for site-build / site-up)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[36m'; RESET=$'\033[0m'
errors="${LITE_CHECK_ERRORS:-0}"; warnings=0   # LITE_CHECK_ERRORS: failures already reported by lite-site check
info()  { echo "${BLUE}==>${RESET} $*"; }
ok()    { echo "${GREEN}ok${RESET}   $*"; }
warn()  { echo "${YELLOW}warn${RESET} $*"; warnings=$((warnings + 1)); }
fail()  { echo "${RED}FAIL${RESET} $*"; errors=$((errors + 1)); }
hint()  { echo "     $*"; }
die()   { echo "${RED}error${RESET} $*" >&2; exit 1; }

site="${1:-}"; [ -n "$site" ] || die "usage: $0 <site>"
SITE_DIR="lite/sites/$site"
[ -f "$SITE_DIR/site.env" ] || die "$SITE_DIR/site.env not found (make site-add SITE=$site)"
set -a
# shellcheck disable=SC1090
. "$SITE_DIR/site.env"
set +a
: "${SITE_CODE_DIR:=$SITE_DIR/repo}"
: "${SITE_THEMES:=}"
: "${SITE_SOLR_CORE:=dsu_multisite}"
: "${SITE_PLACEHOLDERS:=relink}"

DB_DIR="$SITE_DIR/db"
NORMALIZED="$DB_DIR/$site.sql.xz"
CODE="$SITE_CODE_DIR"

# head_of <file>: the first 64 KiB, decompressed. No pipefail here: head closes the pipe
# early on purpose, which would otherwise fail the decompressor.
head_of() {
  set +o pipefail
  case "$1" in
    *.xz) xz -dc "$1" 2>/dev/null | head -c 65536 ;;
    *.gz) gzip -dc "$1" 2>/dev/null | head -c 65536 ;;
    *)    head -c 65536 "$1" ;;
  esac
  set -o pipefail
}

# tar_count_ibd <tarball>: .ibd entries among the first 2000 listed.
tar_count_ibd() {
  set +o pipefail
  tar -tzf "$1" 2>/dev/null | head -2000 | grep -c '\.ibd$' || true
  set -o pipefail
}

# ---------------------------------------------------------------------------------------
info "[1/7] site.env"
env_ok=1
for name in $SITE_THEMES; do
  case "$name" in
    */*)
      fail "SITE_THEMES entry '$name' is a path; list folder names under $SITE_DIR/themes/"
      hint "e.g. SITE_THEMES=$(basename "$name")"
      env_ok=0 ;;
  esac
done
case "$SITE_PLACEHOLDERS" in
  relink|per-file|false) ;;
  *) fail "SITE_PLACEHOLDERS='$SITE_PLACEHOLDERS' (expected relink, per-file or false)"; env_ok=0 ;;
esac
case "$SITE_SOLR_CORE" in
  ''|*[!a-z0-9_-]*) fail "SITE_SOLR_CORE='$SITE_SOLR_CORE' (lowercase letters, digits, '-' or '_')"; env_ok=0 ;;
esac
[ -n "${PROD_DOMAIN:-}" ] || warn "PROD_DOMAIN is empty: the first start cannot list config that still names the production host"
[ "$env_ok" = 1 ] && ok "site.env (themes: ${SITE_THEMES:-none}, Solr core: $SITE_SOLR_CORE, placeholders: $SITE_PLACEHOLDERS)"

# ---------------------------------------------------------------------------------------
info "[2/7] code: $CODE"
code_ok=0
if [ ! -d "$CODE" ]; then
  fail "$CODE does not exist"
  hint "git clone <internal GitHub URL of the site's composer project> $SITE_DIR/repo"
  hint "or point SITE_CODE_DIR in $SITE_DIR/site.env at an existing checkout"
elif [ ! -f "$CODE/config/sync/core.extension.yml" ]; then
  fail "$CODE has no config/sync/core.extension.yml (not the site's composer project, or config not exported)"
  [ -n "$(ls -A "$CODE" 2>/dev/null)" ] || hint "the folder is empty: clone the repo into it"
else
  code_ok=1
  # Only trust git when $CODE is the top of its own checkout: a copied folder without .git
  # would otherwise report the isle-site-lite repository it sits in.
  if [ "$(git -C "$CODE" rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$CODE" && pwd -P)" ]; then
    commit="$(git -C "$CODE" rev-parse --short HEAD 2>/dev/null || echo 'no commits')"
    branch="$(git -C "$CODE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
    ok "composer project with config/sync ($(ls "$CODE/config/sync" | wc -l | tr -d ' ') files; $branch @ $commit)"
    if [ -n "$(git -C "$CODE" status --porcelain 2>/dev/null | head -1)" ]; then
      warn "$CODE has uncommitted changes; they will be staged as they are"
    fi
  else
    ok "composer project with config/sync ($(ls "$CODE/config/sync" | wc -l | tr -d ' ') files)"
    warn "$CODE is not a git checkout: NOTES.md cannot record which commit was used"
  fi
  [ -f "$CODE/config/sync/system.theme.yml" ] || warn "no config/sync/system.theme.yml: the default theme cannot be checked"
fi

# ---------------------------------------------------------------------------------------
info "[3/7] themes: ${SITE_THEMES:-(none listed in SITE_THEMES)}"
if find "$SITE_DIR/themes" -maxdepth 1 -name '*.info.yml' 2>/dev/null | grep -q .; then
  top="$(basename "$(find "$SITE_DIR/themes" -maxdepth 1 -name '*.info.yml' | head -1)")"
  fail "$SITE_DIR/themes/ holds a theme's files directly ($top); each theme needs its own folder"
  hint "mkdir $SITE_DIR/themes/<name> and move the files into it, then SITE_THEMES=<name>"
fi
provided_dirs=""
for name in $SITE_THEMES; do
  case "$name" in */*) continue ;; esac
  src="$SITE_DIR/themes/$name"
  if [ ! -d "$src" ]; then
    fail "theme '$name' is not at $src"
    hint "git clone <theme repo URL> $src   (or copy an existing checkout there)"
    continue
  fi
  info_yml="$(find "$src" -maxdepth 1 -name '*.info.yml' | head -1)"
  if [ -z "$info_yml" ]; then
    fail "no *.info.yml at the top of $src; is this a Drupal theme?"
    continue
  fi
  ok "theme folder $name ($(basename "$info_yml" .info.yml))"
  provided_dirs="$provided_dirs $src"
done
for d in "$SITE_DIR"/themes/*/; do
  [ -d "$d" ] || continue
  d="$(basename "$d")"
  case " $SITE_THEMES " in *" $d "*) ;; *) warn "themes/$d is not listed in SITE_THEMES and will not be staged" ;; esac
done
[ -d "$CODE/web/themes/custom" ] && provided_dirs="$provided_dirs $CODE/web/themes/custom"

# Same rule as intake: every theme the config enables is core, contrib shipped by the Lite
# composer set, or provided here.
if [ "$code_ok" = 1 ]; then
  known_themes='olivero|claro|stark|stable|stable9|classy|seven|bartik|starterkit_theme|bootstrap_barrio|carapace'
  wanted="$( { sed -n '/^theme:/,/^[a-z]/p' "$CODE/config/sync/core.extension.yml" | grep -E '^[[:space:]]+[a-z0-9_]+:' | sed -E 's/^[[:space:]]+([a-z0-9_]+):.*/\1/'; grep -E '^(default|admin):' "$CODE/config/sync/system.theme.yml" 2>/dev/null | cut -d: -f2 | tr -d ' '; } | sort -u )"
  missing=""
  for t in $wanted; do
    echo "$t" | grep -Eqx "$known_themes" && continue
    found=0
    for d in $provided_dirs; do
      if find "$d" -name "$t.info.yml" | grep -q .; then found=1; break; fi
    done
    [ "$found" = 1 ] || missing="$missing $t"
  done
  if [ -n "$missing" ]; then
    fail "config enables theme(s) not provided:$missing"
    hint "put each under $SITE_DIR/themes/<dir>/ (with <theme>.info.yml at its top) and add <dir> to SITE_THEMES"
  else
    ok "every enabled theme is provided ($(echo $wanted | tr '\n' ' '))"
  fi
fi

# ---------------------------------------------------------------------------------------
info "[4/7] database handover in $DB_DIR"
shopt -s nullglob
dumps=(); tarballs=()
for f in "$DB_DIR"/*.sql "$DB_DIR"/*.sql.gz "$DB_DIR"/*.sql.xz "$DB_DIR"/incoming/*.sql "$DB_DIR"/incoming/*.sql.gz "$DB_DIR"/incoming/*.sql.xz; do
  [ "$f" = "$NORMALIZED" ] && continue
  dumps+=("$f")
done
for f in "$DB_DIR"/*.tar.gz "$DB_DIR"/*.tgz "$DB_DIR"/incoming/*.tar.gz "$DB_DIR"/incoming/*.tgz; do
  tarballs+=("$f")
done
others=("$DB_DIR"/*.zip "$DB_DIR"/*.tar "$DB_DIR"/*.7z "$DB_DIR"/*.bz2 "$DB_DIR"/*.ibd)
shopt -u nullglob

for f in ${dumps[@]+"${dumps[@]}"}; do
  if head_of "$f" | grep -Eq 'MySQL dump|MariaDB dump|CREATE TABLE|INSERT INTO'; then
    ok "mysqldump: ${f#"$SITE_DIR"/} ($(du -h "$f" | cut -f1))"
  else
    fail "${f#"$SITE_DIR"/} does not look like a mysqldump (no dump header, CREATE TABLE or INSERT in its first 64 KiB)"
  fi
done
for f in ${tarballs[@]+"${tarballs[@]}"}; do
  n="$(tar_count_ibd "$f")"
  if [ "${n:-0}" -gt 0 ]; then
    ok ".ibd archive: ${f#"$SITE_DIR"/} ($(du -h "$f" | cut -f1); $n .ibd files among the first entries)"
  else
    fail "${f#"$SITE_DIR"/} lists no .ibd files in its first 2000 entries (not a raw MySQL data archive?)"
  fi
done
for f in ${others[@]+"${others[@]}"}; do
  fail "${f#"$SITE_DIR"/}: unsupported format; intake takes *.sql, *.sql.gz, *.sql.xz or a .tar.gz/.tgz of .ibd files"
done
if [ "${#dumps[@]}" -gt 0 ] && [ "${#tarballs[@]}" -gt 0 ]; then
  warn "both a dump and an .ibd archive are present; intake uses the dump"
fi
if [ -s "$NORMALIZED" ]; then
  ok "normalized dump present: ${NORMALIZED#"$SITE_DIR"/} ($(du -h "$NORMALIZED" | cut -f1)); intake reuses it unless FORCE=1"
elif [ "${#dumps[@]}" -eq 0 ] && [ "${#tarballs[@]}" -eq 0 ]; then
  fail "no database handover in $DB_DIR"
  hint "copy the file you were given there: *.sql, *.sql.gz, *.sql.xz, or a .tar.gz/.tgz of raw MySQL 8.0 .ibd files"
fi

# ---------------------------------------------------------------------------------------
info "[5/7] Solr config in $SITE_DIR/solr/conf (optional)"
SOLR_CONF="$SITE_DIR/solr/conf"
if [ ! -d "$SOLR_CONF" ] || [ -z "$(ls -A "$SOLR_CONF" 2>/dev/null)" ]; then
  warn "no Solr config: if this site creates core $SITE_SOLR_CORE, it gets the config search_api_solr generates"
  hint "cp -R <production Solr core conf/ folder> $SOLR_CONF"
elif [ ! -f "$SOLR_CONF/solrconfig.xml" ] || [ ! -f "$SOLR_CONF/schema.xml" ]; then
  fail "$SOLR_CONF has no solrconfig.xml and schema.xml (expected a Solr core's conf/ folder)"
  [ -f "$SITE_DIR/solr/conf/conf/solrconfig.xml" ] && hint "it holds conf/ inside conf/: move its content up one level"
else
  version="$(sed -n 's/^solr.luceneMatchVersion=//p' "$SOLR_CONF/solrcore.properties" 2>/dev/null | head -1)"
  ok "Solr core config ($(find "$SOLR_CONF" -type f | wc -l | tr -d ' ') files, luceneMatchVersion ${version:-unknown}); intake adapts it to this stack's Solr and test-loads it"
fi

# ---------------------------------------------------------------------------------------
CANTALOUPE_CONF="lite/cantaloupe/conf"
info "[6/7] Cantaloupe config in $CANTALOUPE_CONF (optional, shared by the whole stack)"
if [ ! -d "$CANTALOUPE_CONF" ] || [ -z "$(ls -A "$CANTALOUPE_CONF" 2>/dev/null)" ]; then
  warn "no Cantaloupe config: the cantaloupe service keeps the image's config"
  hint "cp -R <production Cantaloupe config folder>/. $CANTALOUPE_CONF/   (cantaloupe.properties + delegate *.rb)"
elif [ ! -f "$CANTALOUPE_CONF/cantaloupe.properties" ]; then
  fail "$CANTALOUPE_CONF has no cantaloupe.properties"
else
  rb_count="$(find "$CANTALOUPE_CONF" -maxdepth 1 -name '*.rb' | wc -l | tr -d ' ')"
  if grep -Eq '^[[:space:]]*delegate_script\.enabled[[:space:]]*=[[:space:]]*true' "$CANTALOUPE_CONF/cantaloupe.properties"; then
    if [ "$rb_count" != 1 ]; then
      fail "cantaloupe.properties enables the delegate script, but $CANTALOUPE_CONF has $rb_count *.rb files (expected one)"
    else
      ok "cantaloupe.properties + delegate $(basename "$(find "$CANTALOUPE_CONF" -maxdepth 1 -name '*.rb')"); intake translates it for this image and test-starts it"
    fi
  else
    ok "cantaloupe.properties (delegate script disabled); intake translates it for this image and test-starts it"
  fi
fi

# ---------------------------------------------------------------------------------------
info "[7/7] host"
if [ ! -f .env ]; then
  fail ".env not found: run make lite-init first"
fi
if ! docker info >/dev/null 2>&1; then
  fail "docker is not reachable (start Docker Desktop / the docker daemon)"
else
  ok "docker reachable"
fi
if [ "${#tarballs[@]}" -gt 0 ] && [ ! -s "$NORMALIZED" ] && ! command -v python3 >/dev/null 2>&1; then
  fail "python3 not found: .ibd recovery runs lite/intake/sdi2ddl.py on the host"
fi
command -v xz >/dev/null 2>&1 || fail "xz not found: intake writes db/$site.sql.xz"
if [ -f "$SITE_DIR/solr/conf/solrconfig.xml" ] && ! command -v jq >/dev/null 2>&1; then
  fail "jq not found: intake reads Solr's answer when it test-loads solr/conf"
fi

# ---------------------------------------------------------------------------------------
echo
if [ "$errors" -gt 0 ]; then
  echo "${RED}$errors problem(s)${RESET}, $warnings warning(s). Fix the FAIL lines, then: make site-check SITE=$site"
  exit 1
fi
echo "${GREEN}Ready for intake${RESET} ($warnings warning(s)): make site-intake SITE=$site"
