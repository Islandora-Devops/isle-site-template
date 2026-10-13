#!/usr/bin/env bash
#
# Stage a production Cantaloupe config for the stack's shared cantaloupe service. Called
# by intake.sh (step 4) and `make lite-cantaloupe`, with the operator's manual input:
#
#   lite/intake/cantaloupe-conf.sh <src: lite/cantaloupe/conf> <dest: lite/cantaloupe/stage>
#
# src holds production's cantaloupe.properties and, if it enables the delegate script, one
# *.rb delegate. islandora/cantaloupe renders its cantaloupe.properties from CANTALOUPE_*
# variables on every start, so the properties become dest/cantaloupe.env, which
# docker-compose.lite.yml passes to the service (optional env_file); the delegate becomes
# dest/delegates.rb, mounted at /opt/lite/cantaloupe/.
#
# Taken from production: every key the image templates, except the ones that belong to this
# container or to production's infrastructure, which keep the image's values:
#   temp_pathname, http(s).*, base_uri, slash_substitute, delegate_script.pathname, cache and
#   heap-cache paths, *.path_to_binaries, log.* (the container logs to the console),
#   endpoint.admin.* / endpoint.api.* (production credentials are never used), Jdbc*, Redis*,
#   S3*, AzureStorage*, FilesystemSource path prefixes, HttpSource.proxy.*.
# Also left to the image: empty values, values with a backslash escape (the image's
# environment import turns "\n" into a line break and the properties file becomes
# malformed), and processor names this Cantaloupe does not have (JaiProcessor,
# ImageMagickProcessor, GraphicsMagickProcessor were removed in 5.0).
# The delegate: relative Logger paths (the process runs in the root-owned /opt/cantaloupe)
# go to /tmp, then JRuby (from cantaloupe.jar) checks its syntax. Finally a throwaway
# islandora/cantaloupe:$ISLANDORA_TAG (no network) must start with the result and run the
# delegate for a request without errors.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[36m'; RESET=$'\033[0m'
info()  { echo "${BLUE}==>${RESET} $*"; }
ok()    { echo "${GREEN}ok${RESET}  $*"; }
warn()  { echo "${YELLOW}warn${RESET} $*" >&2; }
die()   { echo "${RED}error${RESET} $*" >&2; exit 1; }

src="${1:-}"; dest="${2:-}"
[ -n "$src" ] && [ -n "$dest" ] || die "usage: $0 <src dir> <dest dir>"
props="$src/cantaloupe.properties"
[ -f "$props" ] || die "$props not found (copy production's Cantaloupe config folder to $src)"

tag="$(sed -n 's/^ISLANDORA_TAG=//p' .env 2>/dev/null | tr -d '"'"'" | tail -1)"
[ -n "$tag" ] || die "ISLANDORA_TAG not found in .env (make lite-init first)"
image="islandora/cantaloupe:$tag"

rm -rf "$dest"
mkdir -p "$dest"
dest_abs="$(cd "$dest" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Variables the image's template reads: only these can be set.
docker run --rm --entrypoint cat "$image" /etc/confd/templates/cantaloupe.properties.tmpl \
  | grep -o 'getenv "CANTALOUPE_[A-Z0-9_]*"' | sed 's/getenv "\(.*\)"/\1/' | sort -u > "$tmp/templated"
[ -s "$tmp/templated" ] || die "could not read the property template of $image"

# --- properties -> cantaloupe.env ------------------------------------------------------------
TEMPLATED="$tmp/templated" REPORT="$tmp/report" perl -e '
  use strict; use warnings;
  my %templated; open(my $t, "<", $ENV{TEMPLATED}) or die; while (<$t>) { chomp; $templated{$_} = 1; } close $t;
  my $own = qr/^(?:temp_pathname|https?\.|base_uri$|slash_substitute$|delegate_script\.pathname$|FilesystemCache\.pathname$|HeapCache\.persist\.filesystem\.pathname$|.*\.path_to_binaries$|log\.|endpoint\.(?:admin|api)\.|Jdbc|Redis|S3|AzureStorage|FilesystemSource\.BasicLookupStrategy\.path_|HttpSource\.proxy\.)/;
  my %processors = map { $_ => 1 } qw(Java2dProcessor TurboJpegProcessor OpenJpegProcessor GrokProcessor FfmpegProcessor PdfBoxProcessor KakaduNativeProcessor);
  my (%val, @order);
  while (my $line = <STDIN>) {
    next if $line =~ /^\s*[#!]/ || $line !~ /\S/;
    next unless $line =~ /^\s*([^=\s]+)\s*=\s*(.*?)\s*$/;
    push @order, $1 unless exists $val{$1};
    $val{$1} = $2;
  }
  my (@applied, @own, @empty, @untemplated, @processor, @escaped);
  for my $k (@order) {
    my $v = $val{$k};
    (my $var = "CANTALOUPE_" . uc $k) =~ s/\./_/g;
    if ($k =~ $own) { push @own, $k; next; }
    if ($v eq "") { push @empty, $k; next; }
    if ($v =~ /\\/) { push @escaped, "$k=$v"; next; }
    if (!$templated{$var}) { push @untemplated, "$k=$v"; next; }
    if ($k =~ /^processor\.ManualSelectionStrategy\./ && !$processors{$v}) { push @processor, "$k=$v"; next; }
    print "$var=$v\n"; push @applied, $k;
  }
  open(my $r, ">", $ENV{REPORT}) or die;
  printf $r "   %d production values applied\n", scalar @applied;
  printf $r "   %d kept at this container'"'"'s values (paths, ports, logs, binaries, credentials, other storage)\n", scalar @own;
  printf $r "   %d empty in production, image default kept\n", scalar @empty;
  print  $r "   not settable on this image (no template variable): $_\n" for @untemplated;
  print  $r "   processor not available in this Cantaloupe, image default kept: $_\n" for @processor;
  print  $r "   backslash escape (the image'"'"'s env import breaks the line), image default kept: $_\n" for @escaped;
  close $r;
' < "$props" > "$tmp/cantaloupe.env"
cat "$tmp/report"

# --- delegate script -------------------------------------------------------------------------
delegate_enabled="$(sed -n 's/^CANTALOUPE_DELEGATE_SCRIPT_ENABLED=//p' "$tmp/cantaloupe.env")"
if [ "$delegate_enabled" = "true" ]; then
  shopt -s nullglob; rbs=("$src"/*.rb); shopt -u nullglob
  [ "${#rbs[@]}" -eq 1 ] || die "delegate_script.enabled = true but $src has ${#rbs[@]} *.rb files (expected exactly one delegate script)"
  cp "${rbs[0]}" "$dest/delegates.rb"
  n="$(perl -i -pe '$n += s{Logger\.new\(\s*([\x27"])(?!/)([^\x27"]+)\1}{Logger.new($1/tmp/$2$1}g; END { print STDERR $n // 0 }' "$dest/delegates.rb" 2>&1 >/dev/null)"
  [ "${n:-0}" -gt 0 ] && echo "   delegate: $n relative Logger path(s) moved to /tmp (the working directory is not writable)"
  docker run --rm --entrypoint java -v "$dest_abs:/in:ro" "$image" \
    -cp /opt/cantaloupe/cantaloupe.jar org.jruby.Main -c /in/delegates.rb >/dev/null \
    || die "JRuby rejects the delegate script ${rbs[0]}"
  echo "   delegate: $(basename "${rbs[0]}") -> delegates.rb, syntax OK"
  echo "CANTALOUPE_DELEGATE_SCRIPT_PATHNAME=/opt/lite/cantaloupe/delegates.rb" >> "$tmp/cantaloupe.env"
fi
{
  echo "# Generated by lite/intake/cantaloupe-conf.sh from $props on $(date +'%F %H:%M')."
  echo "# Do not edit: change the manual input and run make site-intake (or make lite-cantaloupe)."
  cat "$tmp/cantaloupe.env"
} > "$dest/cantaloupe.env"

# --- boot test in a throwaway Cantaloupe -----------------------------------------------------
name="lite-cantaloupe-check-$$"
info "checking the result in a throwaway $image"
docker run -d --rm --network none --name "$name" --env-file "$dest/cantaloupe.env" \
  -v "$dest_abs:/opt/lite/cantaloupe:ro" "$image" >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$tmp"' EXIT
up=0
for _ in $(seq 1 60); do
  if docker exec "$name" curl -fsS -o /dev/null http://localhost:8182/ 2>/dev/null; then up=1; break; fi
  sleep 2
done
[ "$up" = 1 ] || die "Cantaloupe did not start with the staged config:
$(docker logs "$name" 2>&1 | grep -iE 'error|exception|malformed' | head -5)"
# One IIIF request runs the delegate (the source fetch itself fails: no network).
docker exec "$name" curl -s -o /dev/null 'http://localhost:8182/iiif/2/http%3A%2F%2Fexample.invalid%2Fcheck.jpg/info.json' || true
sleep 1
if docker logs "$name" 2>&1 | grep -E 'Error during evaluation of Ruby|DelegateException|RaiseException|ScriptException' | head -3 | grep -q .; then
  die "the delegate script fails at runtime:
$(docker logs "$name" 2>&1 | grep -E 'Error during evaluation of Ruby|DelegateException|RaiseException|ScriptException' | head -3)"
fi
ok "Cantaloupe $tag starts with it$([ "$delegate_enabled" = "true" ] && echo " and runs the delegate")"
