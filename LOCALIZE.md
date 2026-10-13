# LOCALIZE: production Islandora Lite sites on isle-site-lite

As-built design and runbook (2026-10-06). Short version for operators:
`lite/sites/README.md`. Per-site facts: `lite/sites/<site>/NOTES.md`.

## 1. Purpose and rules

Bring production Islandora Lite sites up locally, one after another, on the isle-site-lite
stack (upstream `isle-site-template` + Lite, see `README.lite.md`), from handovers that
arrive over time. A handover is **only** the site's composer project and its database.

Rules set by the owner:

| Rule | Where it is enforced |
| --- | --- |
| Database comes as a `mysqldump` file **or** a `.tar.gz` of raw MySQL 8.0 `.ibd` files; both must work | `lite/intake/intake.sh` detects, `normalize-dump.sh` / `ibd-recover.sh` convert |
| Files are never handed over; every media must point at a generic file of its type | `relink-media-placeholders.php` + `ensure-referenced-files.php` at first start |
| Production accounts are never read or ported; accounts come from the Lite dev site | `normalize-dump.sh` drops their rows, `SKIP_TABLES` skips their tablespaces, `lite-accounts-from-lite.sh` copies the Lite accounts |
| `composer.json` / `composer_site.json` / lock always from `islandora-lite-site`; the site's composer project contributes `config/sync` (+ custom code if any) | site image is `FROM` the Lite image |
| Solr layout configurable: shared core like prod (default `dsu_multisite`) or one per site | `SITE_SOLR_CORE` |
| Site code and private themes are placed **manually**; nothing clones them for you | intake verifies and refuses with instructions |
| Each site is a local working folder `lite/sites/<site>/` made by `make site-add`, not versioned | `lite/.gitignore` ignores `sites/*` except `_template/` and `README.md` |
| Several sites may run at once | per-site `drupal-<site>` + `db-<site>`, shared services, hostnames `<site>.islandora.io` |
| Upstream files stay untouched | `make lite-upstream-check` prints nothing |

## 2. Architecture

One Compose project (`isle-lite`). Shared: `drupal` (the Lite dev site), `mariadb`,
`solr`, `blazegraph`, `cantaloupe`, `fits`, `traefik`. Per site:

- `db-<site>`: `mysql:8.0` (the handovers are MySQL 8.0; MariaDB and MySQL 8.4 do not load
  them unchanged), seeded on first start from `lite/sites/<site>/db/<site>.sql.xz` through
  `/docker-entrypoint-initdb.d`, TCP healthcheck so Drupal waits for the whole load.
- `drupal-<site>`: image `FROM` the Lite image (`additional_contexts: lite: service:drupal`,
  so Compose builds `drupal` first) plus the site's `config/sync`, themes and `site-files/`,
  and a localize first-start script instead of the Lite install. Served by Traefik at
  `<site>.islandora.io`; the hostname is also a network alias on `traefik` so Cantaloupe,
  FITS and the indexer reach the site from inside the network. The shared Cantaloupe is
  also routed at `<site>.islandora.io/cantaloupe` and the site uses that as its IIIF server, so
  the viewer stays same-origin.
- Both services live in the Compose profile `<site>`; the site's compose file and profile
  are listed in `.env` (`COMPOSE_FILE`, `COMPOSE_PROFILES`) by `make site-enable`.

Everything site-specific is rendered as **literals** into `lite/sites/<site>/docker-compose.yml`
(Compose does not interpolate top-level volume keys and an unset alias renders as `""`).

## 3. Layout

```
isle-site-lite/
├── custom.Makefile                 lite-* and site-* targets (upstream -includes it)
├── docker-compose.lite.yml         Lite override (+ shared Solr core volume solr-core-dsu_multisite on solr)
├── LOCALIZE.md                     this file
├── README.lite.md                  the Lite stack itself
└── lite/
    ├── bin/lite-site               all site-* operations (make targets are thin wrappers)
    ├── bin/timeout                 GNU timeout shim for macOS (upstream scripts need it)
    ├── env.sample                  .env defaults
    ├── drupal/                     Lite image build context (settings.lite.php, Lite install, lite-hydrate.sh)
    ├── site/composer.lock          complete 320-package lock copied over the Lite site clone
    ├── site-image/                 generic production-site image
    │   ├── Dockerfile              FROM lite; config/sync, themes (web/themes/<name>), site-files, scripts
    │   └── rootfs/
    │       ├── etc/s6-overlay/scripts/install.sh        localize first start (gate: state key lite.localized)
    │       ├── usr/local/bin/lite-site-finalize.sh      the localization steps, re-runnable
    │       ├── usr/local/bin/lite-accounts-from-lite.sh accounts from the Lite site
    │       ├── usr/local/bin/lite-solr-conf.sh          create the core from / swap in the site's Solr config
    │       ├── usr/local/bin/mariadb-skip-ssl-wrapper   + symlinks mysql, mysqldump, mysqladmin, mysqlcheck, mariadb*
    │       └── opt/lite/scripts/
    │           ├── lite-placeholders.inc.php            generators (ImageMagick/ffmpeg/stubs), extension and MIME maps
    │           ├── relink-media-placeholders.php        file_managed rows → per-row symlink to a generic file
    │           ├── ensure-referenced-files.php          files named in config / text fields (logo, inline images)
    │           ├── delete-orphan-facets.php             facets whose field exists in no index
    │           ├── make-placeholder-files.php           alternative mode: one file at every original path
    │           └── restore-user-tables.php              recreate missing account tables
    ├── intake/
    │   ├── check.sh                validate the manual inputs (make site-check; also first step of intake)
    │   ├── intake.sh               verify code + themes, stage, database detect/convert, assess
    │   ├── normalize-dump.sh       any dump → db/<site>.sql.xz (no CREATE DATABASE/USE/DEFINER/GTID, no account rows)
    │   ├── solr-conf.sh            solr/conf → stage/solr/conf adapted to this stack's Solr, test-loaded in a throwaway Solr
    │   ├── cantaloupe-conf.sh      lite/cantaloupe/conf → lite/cantaloupe/stage (CANTALOUPE_* env + delegate), test-started
    │   ├── ibd-recover.sh          .ibd tarball → throwaway mysql:8.0 → dump (uses import-ibd.sh, sdi2ddl.py, ibd2sql)
    │   ├── import-ibd.sh, sdi2ddl.py   from the menus work, unchanged
    │   └── assess.sh               report appended to NOTES.md
    ├── cantaloupe/                 the stack's Cantaloupe config (README.md tracked; conf/ and stage/ git-ignored)
    │   ├── conf/                   optional: your copy of production's Cantaloupe folder (properties + delegate *.rb)
    │   └── stage/                  generated by intake: cantaloupe.env + delegates.rb (env_file / mount in docker-compose.lite.yml)
    └── sites/
        ├── README.md               operator guide
        ├── _template/              docker-compose.site.yml, site.env.sample, README.site.md
        └── <site>/                 local working folder from `make site-add` (git-ignored, not versioned)
            ├── site.env, docker-compose.yml, site-files/, NOTES.md, README.md
            ├── repo/               your clone of the site's composer project (= default SITE_CODE_DIR)
            ├── themes/<name>/      your clone/copy of each theme in SITE_THEMES
            ├── db/                 your handover file; intake moves it to db/incoming/ and writes db/<site>.sql.xz
            ├── solr/conf/          optional: your copy of the production Solr core's conf/ folder
            └── stage/, db-raw/     generated by intake
```

## 4. Per-site workflow

Copy-paste version with rebuild and everyday commands: [QUICKSTART.md](QUICKSTART.md).

```bash
# the stack (once)
make lite-init && make lite-up

# a new site
make site-add SITE=memory                  # scaffold lite/sites/memory/ (edit site.env, then: make site-render SITE=memory)

# your manual inputs
git clone <internal GitHub repo> lite/sites/memory/repo                        # or set SITE_CODE_DIR
git clone <theme repo> lite/sites/memory/themes/dsu_subtheme_barrioDepartments  # every name in SITE_THEMES
cp <handover: *.sql | *.sql.gz | *.sql.xz | *.tar.gz of .ibd> lite/sites/memory/db/

# optional (skip either one: nothing fails, the defaults apply)
cp -R <production Solr core conf/ folder> lite/sites/memory/solr/conf             # else: config generated by search_api_solr
cp -R <production Cantaloupe config folder>/. lite/cantaloupe/conf/              # else: the image's config; once for the whole stack

# validate the manual inputs (read-only; repeat until it prints "Ready for intake")
make site-check  SITE=memory

# run (site-intake + site-build + site-up; stops at the first failing step)
make site-deploy SITE=memory
make site-login  SITE=memory             # or log in as admin with secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD
```

`site.env` keys: `SITE_DOMAIN`, `SITE_CODE_DIR`, `SITE_SOLR_CORE` (`dsu_multisite` =
shared, `<site>` = own), `SITE_THEMES`, `SITE_DB_NAME`, `SITE_NAME`, `PROD_DOMAIN`,
`SKIP_TABLES`, `SITE_PLACEHOLDERS` (`relink` | `per-file` | `false`), `SITE_DB_BUFFER_POOL`.
After editing: `make site-render SITE=<site>` (and `make site-up` to apply).

## 5. What intake does (`make site-intake SITE=<site>`)

0. Runs the same validation as `make site-check` (`lite/intake/check.sh` plus the
   rendered compose file against `site.env`) and stops, listing every problem, if it fails.
1. Checks `site.env` and `docker-compose.yml` exist (folder name must equal `SITE`).
2. Code: refuses unless `$SITE_CODE_DIR/config/sync/core.extension.yml` exists; stages
   `config/sync` and `web/{modules,themes}/custom` into `stage/`; records the git commit.
3. Themes: copies `themes/<name>/` → `stage/web/themes/<name>/` for each `SITE_THEMES`
   entry; fails if a theme that `core.extension.yml` / `system.theme.yml` enables (other
   than core themes and `bootstrap_barrio`) has no `<theme>.info.yml` in the staged set.
4. Solr config (optional `solr/conf/`; absent: a warning, the generated config applies): `solr-conf.sh` copies it to `stage/solr/conf`
   (the site image moves it to `/opt/lite/solr/conf`) and adapts it to the Solr 10 of
   `islandora/solr`: drops backup/editor leftovers, `core.properties`, `lib/`, `lib-old/`,
   `data/` and `managed-schema*` (with `ClassicIndexSchemaFactory`); comments out `<lib/>`;
   removes `ExternalFileField` types and their fields, `numVersionBuckets` and
   `<circuitBreaker>`; `LRUCache`/`FastLRUCache`/`LFUCache` are dropped when the same cache
   is declared as `CaffeineCache`, otherwise switched to it. Then a throwaway
   `islandora/solr:$ISLANDORA_TAG` (`--network none`) must create a core from the result,
   or intake stops with Solr's error. Without `solr/conf/`, a warning only.
5. Cantaloupe config (optional `lite/cantaloupe/conf/`, one for the stack; absent: a warning,
   the image's config applies):
   `cantaloupe-conf.sh` turns `cantaloupe.properties` into `lite/cantaloupe/stage/cantaloupe.env`
   (`CANTALOUPE_*`, read by the image's confd template on every start) for every key the image
   templates, except this container's own settings (`temp_pathname`, `http(s).*`, `base_uri`,
   cache/heap paths, `*.path_to_binaries`, `log.*`), production credentials and other storage
   (`endpoint.admin.*`, `endpoint.api.*`, Jdbc, Redis, S3, Azure), empty values, values with a
   backslash escape and processors this Cantaloupe lacks (`JaiProcessor`, ...). The delegate
   (`delegate_script.enabled = true` needs exactly one `*.rb`) becomes `stage/delegates.rb`
   with relative `Logger` paths moved to `/tmp`, JRuby-checked. A throwaway
   `islandora/cantaloupe:$ISLANDORA_TAG` (`--network none`) must start with it and run the
   delegate for one request. `site-up` (and `make lite-cantaloupe`) recreates `cantaloupe`
   when the result changed. Without the input, the stage is removed: image config.
6. Database: moves raw inputs from `db/` to `db/incoming/` (the MySQL container loads every
   `*.sql*` in `db/`), then
   - dump → `normalize-dump.sh` → `db/<site>.sql.xz`;
   - `.ibd` tarball → `ibd-recover.sh`: extract to `db-raw/`, `ibd2sdi` (`mysql:8.0-debian`,
     amd64 emulation) + `sdi2ddl.py` → schema, throwaway `mysql:8.0` + `import-ibd.sh`
     (`DISCARD`/`IMPORT TABLESPACE`, `SKIP_TABLES` left empty), `ibd2sql` for tables
     IMPORT rejected, `mysqldump` → `normalize-dump.sh`; logs in `db/incoming/recovery-<date>/`;
   - a dump wins when both exist; an existing `db/<site>.sql.xz` is reused unless `FORCE=1`.
7. Assess → appended to `NOTES.md`: composer facts, modules not matched to a Lite package,
   Solr servers/cores, facets, hostnames and `public://` files in config, dump facts.

## 6. What the first start does (`install.sh` → `lite-site-finalize.sh`)

Gate: `SELECT COUNT(*) FROM key_value WHERE collection='state' AND name='lite.localized'`
through `execute-sql-file.sh` (no drush bootstrap on restarts). Waits for db, solr, fits
(and blazegraph only if `triplestore_indexer` is enabled). Then, in this order:

1. accounts: `lite-accounts-from-lite.sh` truncates the account tables and copies the Lite
   site's (`mariadb`/`drupal_default`);
2. `lite-hydrate.sh`: Solr servers, IIIF/OpenSeadragon, Mirador, FITS, advancedqueue,
   ffmpeg re-pointed (config:set guarded by config:get; a failing cache rebuild before
   `updb` is tolerated); check that a Solr server now points at `solr`;
3. JWT key (`configure_jwt_module`);
4. Solr core `SITE_SOLR_CORE` (skipped when it already exists: shared mode): created by
   `lite-solr-conf.sh` from the site's staged `solr/conf` when the site has one, otherwise
   from the config search_api_solr generates. On a shared core the first site to start
   decides; `make site-solr-conf SITE=<site>` swaps that site's config into an existing core;
5. `delete-orphan-facets.php` (facets whose field is in no index abort the views updates);
6. `drush updb -y --no-cache-clear`, `cr`, `search-api:reset-tracker` (no `cim`);
7. Blazegraph namespace, only if `triplestore_indexer` is enabled;
8. uid 1 password = `secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD`, unblocked, administrator;
9. `site-files/` copied into `sites/default/files` (never overwriting);
10. placeholders (`SITE_PLACEHOLDERS=relink`): `relink-media-placeholders.php` then
    `ensure-referenced-files.php`, `drush cr`;
11. list of config objects still mentioning `PROD_DOMAIN` (review by hand);
12. `state:set lite.localized`, `drush uli`, `Install Completed`.

Re-run any time with `make site-finalize SITE=<site>` (idempotent). Reindexing is never
started automatically: `make site-drush SITE=<site> CMD="search-api:index"`.

## 7. Files and placeholders

- `relink-media-placeholders.php`: one generic file per (scheme, MIME type) at
  `<scheme>://lite-placeholders/<slug>.<ext>` (ImageMagick for raster images with a
  "PLACEHOLDER - local replica" label, ffmpeg for TIFF/JP2 (rgb24) and audio/video, stubs
  for SVG/PDF/XML/text). Every `file_managed` row is rewritten to **its own** path
  `<scheme>://lite-placeholders/<slug>/<fid div 1000>/<fid>.<ext>`, a relative symlink to
  the generic file. One path per row matters: Drupal's `file_file_download()` loads the
  first file entity with a matching URI and checks access on that one only, so shared URIs
  made private hero images 403 for anonymous users. Originals are kept in
  `lite_file_uri_backup` (fid, uri, filesize). Idempotent: on a fresh volume the generic
  files and symlinks are recreated, and rows are re-pointed if their expected path changed.
- `ensure-referenced-files.php`: paths that are not managed files (theme logo
  `public://logo.svg` in config, inline images `/sites/default/files/inline-images/...` in
  text fields) are found by scanning the `config` table and every text field, and a generic
  file of the extension's type is copied there if missing. Real files from `site-files/`
  are never overwritten.
- `make site-placeholders SITE=<site> [MODE=relink|per-file]` re-runs both.

## 8. Accounts

Never the production ones. `normalize-dump.sh` drops the INSERTs of `users`,
`users_field_data`, `users_data`, `user__roles`, `user__user_picture`, `shortcut_set_users`,
`sessions`, `flood` (both input formats and `make site-dump`); the default `SKIP_TABLES`
keeps those tablespaces unattached in `.ibd` recovery; `lite-accounts-from-lite.sh` copies
the Lite dev site's accounts in (uid 0, `admin`, roles) and the stack password is set on
uid 1. `make site-users-from-lite SITE=<site>` repeats it. `db-<site>` runs with
`--disable-log-bin` so no binary log keeps rows around.

## 9. Make targets (all take `SITE=`; `make help` lists them)

`site-add`, `site-render`, `site-check` (read-only validation of `site.env`, the rendered
compose file, code, themes, database handover, Solr and Cantaloupe config, and host before intake), `site-enable`, `site-disable` (stops the site first:
upstream `up.sh` uses `--remove-orphans`), `site-intake`, `site-build`, `site-up`
(recreates `traefik` and `cantaloupe` if their config changed, starts `db-<site>` + `drupal-<site>`, waits for
`/installed`), `site-deploy` (`site-intake` + `site-build` + `site-up`), `site-down`,
`site-finalize`, `site-placeholders`, `site-users-from-lite`, `site-solr-conf` (swap the
existing core's config for the site's staged `solr/conf`, keep the old as `conf.bak-<ts>`,
RELOAD, restore it if RELOAD fails, reset the site's tracker), `site-drush CMD=`, `site-shell`, `site-login`, `site-db-shell`, `site-dump [DEST=]`
(through the account filter, `.sql.xz`), `site-reset` (destructive for that site:
containers, volumes, image, `stage/`, normalized dump; keeps `site.env`, `site-files/`,
`NOTES.md`, `repo/`, `themes/`, `db/incoming/`), `sites`.

Plain `make up` / `make down` include enabled sites. `make clean` (upstream) removes site
volumes too. `make lite-upstream-check` must stay empty; `make lite-upstream-pull` merges
upstream (remote `upstream` if present, else `origin`).

## 10. Verification checklist (what "working" meant for memory)

- `docker compose config --services` shows the six shared services plus `db-<site>`,
  `drupal-<site>`; `config traefik` lists the alias; `config solr` the core mount.
- `make site-intake`: `db/<site>.sql.xz` present, `NOTES.md` has the report (tables,
  recovered tables, theme check, module gaps).
- `make site-up` ends with `Site available at: http://<site>.islandora.io` and a login link;
  `docker compose ps` shows both site containers healthy; the Lite site still answers.
- Front page 200 with the site's theme; `drush status` Drupal 11.4.x; node count matches.
- Logo, hero image styles (public and private, anonymous), theme images: 200. Every
  `file_managed` URI resolves to a file; `SELECT COUNT(DISTINCT uri) = COUNT(*)`.
- Solr: core exists, `search-api:server-list` enabled, `search-api:status` tracked counts.
- Cantaloupe: `getent hosts <site>.islandora.io` inside `cantaloupe` resolves to Traefik;
  `info.json` and `/full/!300,300/0/default.jpg` for a public placeholder: 200.
- Accounts: `users_field_data` holds only the Lite accounts; login as `admin` works.
- `make site-down && make site-up`: `Already Installed`, data intact.
- Second format: `make site-dump`, `site-reset`, `site-intake`, `site-build`, `site-up`.

## 11. Troubleshooting (every failure met so far, and its rule)

| Symptom | Cause | Rule |
| --- | --- | --- |
| first start: "database is empty" although MySQL loaded it | `execute-sql-file.sh` validates with `mysqladmin`, which hit MySQL 8's self-signed cert | every MariaDB client (`mysql*`, `mariadb*`) goes through the `--skip-ssl` wrapper |
| `drush cache:rebuild` fails before `updb` (`router.alias`) | Drupal 10.6 data, 11.4 code | tolerate; `updb` rebuilds caches |
| "no Solr server points at solr" though config is right | `php:eval` with `exit()` codes under s6 | compare `config:get --include-overridden` values |
| pages throw `MemcacheException` | prod enables `memcache`, image has no memcached | `settings.lite.php` sets empty `memcache` servers/bins |
| Cantaloupe 500, alias resolves to 127.0.0.1 inside containers | `traefik` not recreated after the alias was added | `site-up` runs `docker compose up -d --no-deps traefik` |
| private hero images 403 for anonymous | shared placeholder URI; access checked on the first matching file row | per-row symlink paths |
| logo / inline images 404 | not managed files | `ensure-referenced-files.php` |
| indexing "Couldn't index items"; Solr 400 "possible analysis error" | the generic `<placeholder>` XML lands in the hOCR field and the OCR highlighting plugin rejects the document | `application/xhtml+xml` placeholders are a minimal valid hOCR page (`lite_placeholder_hocr()`) |
| Solr 400 "Unable to create core ... Caused by: solr.ExternalFileField" with production's Solr config | the config is search_api_solr's Solr 9.8 output; `islandora/solr` runs Solr 10 | intake (`solr-conf.sh`) removes what Solr 10 dropped: `ExternalFileField` (`eff_*`), `<lib/>` directives and the bundled OCR jar (the image ships its own in `/opt/solr/lib`), `LRUCache`/`FastLRUCache`, `numVersionBuckets`, `CircuitBreakerManager`, and test-loads the result in a throwaway `islandora/solr`; a new incompatibility fails intake with Solr's message: extend `solr-conf.sh` |
| cantaloupe never answers; log ends with `Line 633 is malformed.` | a production value with `\n` (overlay string): the image's env import writes a real line break into `cantaloupe.properties` | `cantaloupe-conf.sh` keeps the image default for values with a backslash escape |
| IIIF 500 "Error during evaluation of Ruby ... (EACCES) Permission denied - error.log" | production's delegate logs to a relative `error.log`; the process runs in the root-owned `/opt/cantaloupe` | `cantaloupe-conf.sh` moves relative `Logger.new` paths to `/tmp`; its test request catches delegate runtime errors |
| private images 403 in the viewer while logged in | Cantaloupe fetched the source without the viewer's session | production's delegate (`httpsource_resource_info`) forwards `Cookie` and `Authorization`; supply it in `lite/cantaloupe/conf/` |
| server page: "error ... retrieve additional information ... endpoint not found (404)" | Solr 10 dropped `admin/mbeans`, which search_api_solr 4.4 calls for stats | cosmetic; ping, core and indexing are unaffected |
| `/themes/<dir>/images/...` 404 | theme staged under `web/themes/custom/` | stage at `web/themes/<name>/` |
| media 404 after `site-reset` with a post-relink dump | rows already generic, files not regenerated | relink recreates files/symlinks for already-generic rows |
| theme check lists `name: 0` | BSD `sed`/`grep` have no `\s` | POSIX classes `[[:space:]]` |
| `normalize-dump` "no CREATE TABLE" | `pipefail` + `grep -q` kills the decompressor; `case` patterns inside `$( )` | `grep -c` and a function |
| MySQL seed slow with redo-log warnings | defaults | `--innodb-redo-log-capacity=1G --innodb-flush-log-at-trx-commit=0` |
| `WARN: no uid 1 account` | `drush sql:query` prints a trailing blank line | `awk 'NF {v=$0} END {print v}'` |
| `make lite-upstream-check` cannot fetch | SSH remote without a key in this shell | fetch failure is a warning; compare against the last fetched ref |
| `make up` on macOS fails/hangs after install | upstream scripts need GNU `timeout` | `lite/bin/timeout` on PATH when missing |
| viewer: CORS "Request header field token is not allowed" (logged in) | Mirador sends `Authorization` + `token`; Cantaloupe's preflight allows only `Authorization`, and `islandora.io/cantaloupe` is cross-origin for `<site>.islandora.io` | each site routes `/cantaloupe` on its own host (`<site>-cantaloupe` router) and uses it as `DRUPAL_DEFAULT_CANTALOUPE_URL` |

## 12. History

- 2026-10-05: plan approved (two DB formats, configurable Solr, no files, manual code and
  theme placement, one repo per site, several sites at once).
- 2026-10-06: memory localized from its `.ibd` tarball (334 tables attached, 0 failed,
  `updb` 10.6 → 11.4.8 clean, 105,091 files relinked, 41,206 nodes); dump-format round
  trip (`site-dump` → `site-reset` → `site-intake` → `site-up`) verified; accounts rule added
  and applied retroactively (production account rows removed from the replica, dumps and
  binary logs); home page review fixed private file access, logo/inline images, theme path.
  Details: `lite/sites/memory/NOTES.md`.
- 2026-10-13: production's Solr core config is a manual input (`lite/sites/<site>/solr/conf/`),
  adapted to Solr 10 and test-loaded by intake (`solr-conf.sh`), created at first start or
  swapped into an existing core with `make site-solr-conf`. memory's (prod `dsu_multisite`,
  adds Arabic/French and `text_dsu_en`/`text_dsu_phonetic_en` types) was applied to the
  running core (RELOAD, no documents lost, indexing and search verified).
- 2026-10-13: production's Cantaloupe config is a manual input for the stack
  (`lite/cantaloupe/conf/`), translated to `CANTALOUPE_*` + delegate and test-started by intake,
  applied by `site-up` / `make lite-cantaloupe`. With prod's delegate, private images load
  through Cantaloupe for a logged-in user (403 before); anonymous still 403.
- 2026-10-06: site folders are no longer their own git repos: `lite/sites/<site>/` is a
  local working folder scaffolded by `make site-add` (no `git init`, no site-repo clone).
