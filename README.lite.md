# Islandora Lite on isle-site-template

This repository is an unmodified clone of
[Islandora-Devops/isle-site-template](https://github.com/Islandora-Devops/isle-site-template)
(branch `lite`; `origin` is the digitalutsc fork, add `upstream` for the Islandora-Devops
repo) plus the files below. Production-site replicas on top of it are described in
`LOCALIZE.md` and `lite/sites/README.md`.

| Ours | Purpose |
| --- | --- |
| `custom.Makefile` | `lite-*` and `site-*` targets (`make help` lists them) |
| `docker-compose.lite.yml` | override: disables everything but drupal, mariadb, solr, blazegraph, cantaloupe, fits, traefik; points `drupal` at `lite/drupal`; shared Solr core volume for replicas; optional Cantaloupe config from `lite/cantaloupe/stage/` |
| `lite/env.sample` | `.env` defaults (`isle-lite`, `islandora.io`, `ISLANDORA_TAG`) |
| `lite/drupal/` | Lite drupal image: Dockerfile, env-driven `settings.lite.php`, s6 first-start install, `lite-hydrate.sh`, D11-safe drush settings command |
| `lite/site/` | the complete `composer.lock` (320 packages) copied over the site clone; the lock committed on `drupal-11` lacks the `composer_site.json` packages |
| `lite/bin/` | `lite-site` (all `site-*` operations), `timeout` shim for macOS |
| `lite/site-image/` | generic production-site image (FROM the Lite image) and its localize scripts |
| `lite/intake/` | handover intake: dump normalization, `.ibd` recovery, Solr and Cantaloupe config adaptation, assess |
| `lite/cantaloupe/` | the stack's Cantaloupe config: your copy of production's in `conf/`, generated `stage/` (both git-ignored; see its README) |
| `lite/sites/` | one local working folder per production site, made by `make site-add` (ignored here except `_template/` and `README.md`) |
| `LOCALIZE.md` | design, runbook and troubleshooting for the production-site replicas |

## Quick start

```bash
make lite-init      # .env, override symlink, site clone + overlay, secrets, certs, image build
make lite-up        # upstream `make up` (starts the stack, waits for "Install Completed") + lite-ping
make lite-login     # drush uli
```

macOS note: upstream scripts need GNU `timeout`. When the host has none,
`custom.Makefile` puts `lite/bin/timeout` (a perl shim) on `PATH` for every make target,
so plain `make up` works too. `make lite-ping` is an extra readiness check.

Site: http://islandora.io (admin password: `cat secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD`).
Dev-mode URLs: http://solr.islandora.io, http://blazegraph.islandora.io/bigdata/,
http://islandora.io/cantaloupe/iiif/2/, http://traefik.islandora.io.

HTTPS: `make traefik-https-mkcert && make down-traefik up && make lite-hydrate`
(and `make site-finalize SITE=<site>` for each replica).

## Everyday

```bash
make lite-drush CMD="status"      # any drush command
make lite-shell                   # shell in the drupal container
make lite-hydrate                 # re-point Solr/Blazegraph/IIIF/FITS config at this stack
make lite-cantaloupe              # apply lite/cantaloupe/conf (production's Cantaloupe config) to cantaloupe
make lite-status                  # upstream status + active/disabled services
make sites                        # production replicas and their state
make down / make up               # stop / start (enabled replicas included), data kept
make clean                        # upstream: DESTRUCTIVE, removes volumes (replicas too), secrets, certs, .env
```

The Lite site tree lives at `lite/drupal/rootfs/var/www/drupal` (a clone of
`digitalutsc/islandora-lite-site`, branch `drupal-11`, git-ignored here). It is baked
into the image: after changing it, `make build && make up`. Replica images are built
`FROM` that image, so rebuild them too (`make site-build SITE=<site>`).

## Updating from upstream

```bash
make lite-upstream-check   # must print nothing: no upstream file is modified
make lite-upstream-pull    # fetch + merge upstream main, lists mirrored files that changed
```

Then port changes by hand from `sample.env`, `docker-compose.yml`, `drupal/Dockerfile`
and `drupal/rootfs/etc/s6-overlay/` into their `lite/` mirrors (`lite/env.sample`,
`docker-compose.lite.yml`, `lite/drupal/Dockerfile`, `lite/drupal/rootfs/etc/s6-overlay/`).
The site-image and intake code depend only on the Lite image and the isle-buildkit helpers
(`/etc/islandora/utilities.sh`, `execute-sql-file.sh`).

## Production sites

Each production Islandora Lite site runs as an add-on in `lite/sites/<site>/` (a local,
git-ignored working folder): `make site-add SITE=<site>`, put the code, theme(s) and database handover in that
folder, then `make site-deploy SITE=<site>` (`site-intake` + `site-build` + `site-up`).
Copy-paste steps: `QUICKSTART.md`.
Handovers are composer project + database only: files are replaced by generic placeholders
and accounts by the Lite dev site's. See `lite/sites/README.md` and `LOCALIZE.md`.
