#!/usr/bin/env bash
#
# Stage a production Solr core config for a replica: copy, adapt to the Solr of this stack,
# then prove it loads. Called by intake.sh (step 3) with the site's manual input:
#
#   lite/intake/solr-conf.sh <src: lite/sites/<site>/solr/conf> <dest: stage/solr/conf>
#
# Production runs search_api_solr's Solr 9.x config; islandora/solr runs Solr 10, which
# refuses to create a core from it. The adaptations mirror what search_api_solr's own
# Solr 10 config does differently, and are no-ops on a config that is already adapted:
#   - drop editor/backup leftovers, core.properties, data/, lib/ and lib-old/ (the OCR
#     highlighting jar is in the image's /opt/solr/lib, built for its Solr), and
#     managed-schema* when solrconfig uses ClassicIndexSchemaFactory with a schema.xml
#   - comment out active <lib/> directives (removed in Solr 10; modules come from SOLR_MODULES)
#   - remove ExternalFileField types and the fields using them (removed in Solr 10)
#   - LRUCache/FastLRUCache/LFUCache: dropped when the same cache is also declared as
#     CaffeineCache, otherwise switched to CaffeineCache
#   - remove numVersionBuckets and the <circuitBreaker> block
# Then a throwaway islandora/solr:$ISLANDORA_TAG container (no network) creates a core from
# the result; any error fails the intake with Solr's message.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[36m'; RESET=$'\033[0m'
info()  { echo "${BLUE}==>${RESET} $*"; }
ok()    { echo "${GREEN}ok${RESET}  $*"; }
die()   { echo "${RED}error${RESET} $*" >&2; exit 1; }

src="${1:-}"; dest="${2:-}"
[ -n "$src" ] && [ -n "$dest" ] || die "usage: $0 <src conf dir> <dest conf dir>"
[ -f "$src/solrconfig.xml" ] || die "$src has no solrconfig.xml (expected a Solr core's conf/ folder)"

rm -rf "$dest"
mkdir -p "$dest"
cp -R "$src/." "$dest/"

# --- leftovers ---------------------------------------------------------------------------
find "$dest" \( -name '*.BAK' -o -name '*.bak' -o -name '*.orig' -o -name '*-DELETE' -o -name '*~' \
  -o -name '.DS_Store' -o -name 'core.properties' \) -type f -print -delete | sed "s|^$dest/|   removed |"
for d in lib lib-old data; do
  [ -e "$dest/$d" ] && rm -rf "${dest:?}/$d" && echo "   removed $d/"
done
if [ -f "$dest/schema.xml" ] && grep -q 'ClassicIndexSchemaFactory' "$dest"/solrconfig*.xml; then
  for f in "$dest"/managed-schema "$dest"/managed-schema.xml; do
    [ -e "$f" ] && rm -f "$f" && echo "   removed $(basename "$f") (ClassicIndexSchemaFactory reads schema.xml)"
  done
fi

# --- Solr 10 adaptations -----------------------------------------------------------------
# One perl pass over every XML file; prints what it changed.
DEST="$dest" perl -e '
  use strict; use warnings;
  my $dir = $ENV{DEST};
  opendir(my $dh, $dir) or die "$dir: $!"; my @xml = sort grep { /\.xml$/ } readdir($dh); closedir($dh);
  my %text; for my $f (@xml) { local $/; open(my $fh, "<", "$dir/$f") or die; $text{$f} = <$fh>; close $fh; }

  # ExternalFileField type names, and the cache keys (element + name) declared as CaffeineCache.
  my (%eff, %caffeine);
  for my $t (values %text) {
    $eff{$1} = 1 while $t =~ /<fieldType\b[^>]*\bname="([^"]+)"[^>]*class="solr\.ExternalFileField"/g;
    $eff{$1} = 1 while $t =~ /<fieldType\b[^>]*class="solr\.ExternalFileField"[^>]*\bname="([^"]+)"/g;
    while ($t =~ /<(\w+)\b([^>]*)class="solr\.CaffeineCache"([^>]*)>/g) {
      my ($el, $attrs) = ($1, "$2 $3"); my $name = $attrs =~ /\bname="([^"]+)"/ ? $1 : "";
      $caffeine{"$el:$name"} = 1;
    }
  }

  for my $f (@xml) {
    my @out; my $in_comment = 0; my %n;
    for my $line (split /(?<=\n)/, $text{$f}) {
      if (!$in_comment) {
        if ($line =~ /^(\s*)(<lib\b[^>]*\/>)\s*$/) {
          $line = "$1<!-- Solr 10: <lib/> removed; modules come from SOLR_MODULES. $2 -->\n"; $n{lib}++;
        } elsif ($line =~ /<fieldType\b[^>]*class="solr\.ExternalFileField"/) {
          $n{eff_type}++; next;
        } elsif ($line =~ /<(?:dynamicField|field)\b[^>]*\btype="([^"]+)"/ && $eff{$1}) {
          $n{eff_field}++; next;
        } elsif ($line =~ /<int name="numVersionBuckets">/) {
          $n{numVersionBuckets}++; next;
        } elsif ($line =~ /<(\w+)\b([^>]*)class="solr\.(?:search\.)?(?:LRUCache|FastLRUCache|LFUCache)"([^>]*)>/) {
          my ($el, $attrs) = ($1, "$2 $3"); my $name = $attrs =~ /\bname="([^"]+)"/ ? $1 : "";
          if ($caffeine{"$el:$name"}) { $n{cache_dropped}++; next; }
          $line =~ s/class="solr\.(?:search\.)?(?:LRUCache|FastLRUCache|LFUCache)"/class="solr.CaffeineCache"/; $n{cache_switched}++;
        }
      }
      push @out, $line;
      # Track <!-- --> state across lines (in order of appearance on this line).
      my $copy = $line;
      while ($copy =~ /(<!--|-->)/g) { $in_comment = ($1 eq "<!--") ? 1 : 0; }
    }
    my $new = join("", @out);
    my $cb = 0;
    $cb++ while $new =~ s/\n[ \t]*<circuitBreaker\b.*?<\/circuitBreaker>[ \t]*//s;
    $n{circuitBreaker} = $cb if $cb;
    next unless %n;
    open(my $fh, ">", "$dir/$f") or die; print $fh $new; close $fh;
    print "   $f: ", join(", ", map { "$_ x$n{$_}" } sort keys %n), "\n";
  }
'

# --- validate in a throwaway Solr ---------------------------------------------------------
tag="$(sed -n 's/^ISLANDORA_TAG=//p' .env 2>/dev/null | tr -d '"'"'" | tail -1)"
[ -n "$tag" ] || die "ISLANDORA_TAG not found in .env (make lite-init first)"
image="islandora/solr:$tag"
name="lite-solr-conf-check-$$"
info "checking the adapted config in a throwaway $image"
docker run -d --rm --network none --name "$name" "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
for _ in $(seq 1 60); do
  docker exec "$name" curl -fsS 'http://localhost:8983/solr/admin/cores?action=STATUS&wt=json' >/dev/null 2>&1 && break
  sleep 2
done
docker exec -u 0 "$name" mkdir -p /opt/solr/server/solr/check/data
docker cp -q "$dest" "$name":/opt/solr/server/solr/check/conf
docker exec -u 0 "$name" chown -R 100:1000 /opt/solr/server/solr/check
result="$(docker exec "$name" curl -s 'http://localhost:8983/solr/admin/cores?action=CREATE&name=check&instanceDir=check&config=solrconfig.xml&dataDir=data&wt=json')"
if [ "$(echo "$result" | jq -r '.responseHeader.status')" != "0" ]; then
  die "Solr $tag cannot create a core from the adapted config: $(echo "$result" | jq -r '.error.msg // .')
Fix $src (or extend the adaptations in $0), then run make site-intake again."
fi
types="$(docker exec "$name" curl -s 'http://localhost:8983/solr/check/schema/fieldtypes?wt=json' | jq '.fieldTypes | length')"
ok "Solr $tag loads it ($types field types)"
