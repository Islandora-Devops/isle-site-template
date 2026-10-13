# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Islandora Lite (Drupal 11) on top of the upstream ISLE template. It is the digitalutsc fork of
`Islandora-Devops/isle-site-template` (`origin` = `digitalutsc/isle-site-template`; main branch `lite`,
working branch `lite-localized`). The docs call it "isle-site-lite". Compose project `isle-lite`,
served at `http://islandora.io` (`*.islandora.io` resolves to 127.0.0.1).

**Hard rule: upstream files are never edited.** Everything Lite lives in `custom.Makefile`,
`docker-compose.lite.yml`, `lite/`, `README.lite.md`, `LOCALIZE.md`, `QUICKSTART.md` and this file
(the `LITE_OWN_FILES` list in `custom.Makefile`; add new top-level files there). `make lite-upstream-check` must print
nothing. Upstream's `Makefile`, `docker-compose.yml`, `sample.env`, `drupal/` (the upstream starter
site, **not** used by Lite) and `scripts/` stay as shipped. When upstream changes one of the mirrored files,
port the change by hand into its `lite/` mirror (`sample.env` → `lite/env.sample`, `docker-compose.yml` →
`docker-compose.lite.yml`, `drupal/Dockerfile` → `lite/drupal/Dockerfile`, `drupal/rootfs/etc/s6-overlay/` →
`lite/drupal/rootfs/etc/s6-overlay/`).

Docs: `README.lite.md` (the stack), `LOCALIZE.md` (replica design, first-start steps, troubleshooting
table of every failure met so far, history), `QUICKSTART.md` (copy-paste per-site steps),
`lite/sites/README.md` (operator guide). Read the troubleshooting table in `LOCALIZE.md` §11 before
debugging a replica.

## Commands (repo root)

```bash
make help                       # all targets (upstream + lite-* + site-*)
make lite-init && make lite-up  # .env from lite/env.sample, override symlink, site clone + lock overlay, secrets/certs, build, start
make build && make up           # after changing the Lite site tree or lite/drupal/
make lite-drush CMD="status"    # drush in the Lite drupal container
make lite-shell / lite-login / lite-hydrate / lite-status
make lite-cantaloupe            # lite/cantaloupe/conf (prod Cantaloupe config) -> translate, test, recreate cantaloupe
make lite-upstream-check        # must print nothing
make lite-upstream-pull         # merge upstream main, list mirrored files that changed

make sites                                   # replicas with enabled/running state
make site-add SITE=x && make site-render SITE=x
make site-check SITE=x                       # read-only validation of manual inputs
make site-deploy SITE=x                      # site-intake + site-build + site-up
make site-drush SITE=x CMD="search-api:index"
make site-finalize SITE=x                    # re-run first-start localization (idempotent)
make site-solr-conf SITE=x                   # site's solr/conf -> existing core, RELOAD (then reindex)
make site-reset SITE=x                       # DESTRUCTIVE for that site only
```

`make clean` (upstream) is destructive for everything: volumes (replicas too), secrets, certs, `.env`.
Confirm with the user before running it, `site-reset`, or `docker compose down -v`.

No test suite. CI (`.github/workflows/lint-test.yml`) runs `shellcheck **/*.sh` and hadolint on
upstream `drupal/Dockerfile`; run `shellcheck` on changed shell scripts (including `lite/bin/lite-site`,
which has no `.sh` suffix). Verify changes against the running stack (`make lite-drush CMD=cr`,
`make site-finalize`, loading the site).

## Architecture

**Override, not edits.** `docker-compose.override.yml` is a git-ignored symlink to
`docker-compose.lite.yml`, which moves activemq/alpaca/crayfits/fcrepo/homarus/houdini/hypercube/mergepdf/milliner
into profile `disabled`, unsets the Fedora/broker env vars, points `drupal` at build context `lite/drupal`,
and mounts the shared Solr core volume `solr-core-dsu_multisite`. Running: drupal, mariadb, solr,
blazegraph, cantaloupe, fits (called directly by `media_fits`), traefik.

**Lite image (`lite/drupal/`).** `FROM ${REPOSITORY}/drupal:${ISLANDORA_TAG}` (pinned in `.env`; a
major isle-buildkit bump can change the PHP version, so detect it, never hardcode). Bakes the site tree
from `lite/drupal/rootfs/var/www/drupal`, a git-ignored clone of `digitalutsc/islandora-lite-site`
(branch `drupal-11`) made by `make lite-site`, which then copies `lite/site/composer.lock` (the complete
320-package lock; the committed `drupal-11` lock lacks the `composer_site.json` packages) over it.
`composer install` runs at build time with `use-github-api false` and `safe.directory '*'`. `settings.php`
includes `/etc/islandora/lite/settings.lite.php`, which overrides Solr/IIIF/FITS/Blazegraph/ffmpeg/memcache
config from container env at runtime, so exported config can name other hosts or cores.
First start: s6 `install.sh` (mirrors upstream's) runs `drush si --existing-config`, then
`lite-hydrate.sh` (re-runnable config re-pointing). Also ships a D11-safe `UpdateSettingsCommands.php`.

**Production-site replicas (`lite/sites/<site>/`).** Driven entirely by `lite/bin/lite-site`; the
`site-*` make targets are thin wrappers. Each site folder is a local, git-ignored working folder
(`lite/.gitignore` keeps only `_template/` and `README.md`) holding `site.env`, a `docker-compose.yml`
rendered from `_template/docker-compose.site.yml` with **literal** values (Compose cannot interpolate
top-level volume keys), the operator's manual inputs (`repo/`, `themes/<name>/`, `db/` handover), and
intake output (`stage/`, `db-raw/`, `db/<site>.sql.xz`, `NOTES.md`). Per site, profile `<site>`:
- `db-<site>`: `mysql:8.0` (handovers are MySQL 8.0; not MariaDB, not 8.4), seeded from `db/<site>.sql.xz`.
- `drupal-<site>`: `lite/site-image/Dockerfile`, `FROM lite` (`additional_contexts: lite: service:drupal`)
  plus the staged `config/sync`, custom code, themes at `web/themes/<name>/`, and `site-files/`. Composer
  deps always come from the Lite image; the site only contributes config. Its `install.sh` runs
  `lite-site-finalize.sh` once (gate: state key `lite.localized`).
- Solr core (shared `dsu_multisite` by default): the first site to start creates it with `lite-solr-conf.sh`
  from its optional manual input `solr/conf/` (production core's `conf/`, staged at `/opt/lite/solr/conf`),
  else from the search_api_solr-generated config. An existing core changes only with `make site-solr-conf`.
- `make site-enable` adds the site's compose file and profile to `COMPOSE_FILE`/`COMPOSE_PROFILES` in
  `.env`, so plain `make up`/`down` include enabled sites.
- Hostname `<site>.islandora.io` is also a network alias on `traefik`; each site routes `/cantaloupe` on
  its own host (same-origin for Mirador). `site-up` recreates `traefik` to pick up new aliases.

**Intake (`lite/intake/`).** `check.sh` validates inputs; `intake.sh` stages code/themes and converts the
database: a dump goes through `normalize-dump.sh`; a `.tar.gz` of raw `.ibd` files goes through
`ibd-recover.sh` (`ibd2sdi` in amd64 `mysql:8.0-debian` + `sdi2ddl.py` → schema, throwaway mysql:8.0 +
`import-ibd.sh` DISCARD/IMPORT TABLESPACE, `ibd2sql` for rejected tables, then mysqldump →
normalize). `solr-conf.sh` adapts an optional `solr/conf/` to Solr 10 (production runs 9.x: no `<lib/>`,
`ExternalFileField`, `LRUCache`, `CircuitBreakerManager`) and test-loads it in a throwaway `islandora/solr`.
`cantaloupe-conf.sh` turns the stack-wide optional `lite/cantaloupe/conf/` (prod `cantaloupe.properties` +
delegate) into `lite/cantaloupe/stage/cantaloupe.env` (`CANTALOUPE_*`: the image renders its properties from
env on every start, so the file itself can't be replaced; container paths/ports/logs and prod credentials are
never taken) + `delegates.rb`, passed by `docker-compose.lite.yml` (optional `env_file` + mount), and
test-starts it; `site-up` recreates `cantaloupe` when it changed. `assess.sh` appends a report to `NOTES.md`.

**Owner rules enforced in code** (don't weaken them):
- Production accounts are never used: `normalize-dump.sh` drops account rows, `SKIP_TABLES` skips their
  tablespaces, `lite-accounts-from-lite.sh` copies the Lite site's accounts in (uid 1 = `admin`, password
  in `secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD`).
- Files are never handed over: `relink-media-placeholders.php` rewrites every `file_managed.uri` to a
  per-row symlink (`<scheme>://lite-placeholders/<slug>/<fid div 1000>/<fid>.<ext>`) to one generic file
  per (scheme, MIME); originals are kept in `lite_file_uri_backup`. Per-row paths matter, because private-file
  access is checked against the first row with a matching URI. `ensure-referenced-files.php` covers
  non-managed files (theme logo, inline images).
- Site code and themes are placed manually; scripts verify and refuse with instructions, never clone.

## Gotchas

- macOS: upstream scripts need GNU `timeout`; `custom.Makefile` puts `lite/bin/timeout` (perl shim) on
  `PATH` when missing. Use BSD-safe shell: POSIX classes (`[[:space:]]`), not `\s`.
- MySQL 8's self-signed cert breaks the MariaDB clients in the image: the site image symlinks every
  `mysql*`/`mariadb*` client to `mariadb-skip-ssl-wrapper`.
- `drush` and `composer` run inside containers (`docker compose exec -T drupal with-contenv bash -lc '...'`),
  never on the host.
- Replica images are built `FROM` the Lite image: after changing the Lite site or `lite/drupal/`, rebuild
  the replicas too (`make site-build SITE=x` or `site-deploy`).
- Updating the site tree means rebuilding the image (`make build && make up`). Nothing is bind-mounted.
