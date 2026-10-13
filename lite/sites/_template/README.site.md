# __SITE__: production replica on isle-site-lite

This folder was scaffolded by `make site-add SITE=__SITE__` in
[isle-site-lite](../../../README.lite.md). It is a local working folder, git-ignored and not
versioned (the folder name must stay `__SITE__`), driven with `make site-* SITE=__SITE__`
from the isle-site-lite root.

Here: `site.env` (settings), `docker-compose.yml` (rendered from `site.env`, re-render with
`make site-render`), `site-files/` (small public files named in config, such as the theme
logo), `NOTES.md` (assess report and decisions).

Provided by you:

| Where | What |
| --- | --- |
| `repo/` | the site's Drupal composer project (`git clone <internal GitHub> repo`) |
| `themes/<name>/` | each theme listed in `SITE_THEMES` (private GitHub) |
| `db/` | the database handover: a `mysqldump` file (`.sql`, `.sql.gz`, `.sql.xz`) or a `.tar.gz` of raw MySQL 8.0 `.ibd` files |

Optional (skip either one: nothing fails, the defaults apply):

| Where | What |
| --- | --- |
| `solr/conf/` | the production Solr core's `conf/` folder, copied as is (intake adapts it to this stack's Solr); else the config search_api_solr generates |
| `lite/cantaloupe/conf/` (whole stack, not this folder) | production's Cantaloupe config (see `lite/cantaloupe/README.md`); else the image's config |

Then, from the isle-site-lite root:

```bash
make site-check  SITE=__SITE__   # validate the inputs above (read-only); repeat until "Ready for intake"
make site-deploy SITE=__SITE__   # site-intake + site-build + site-up: stage code/themes, normalize the database, build the image, start; first start localizes (updb, Solr, placeholders)
make site-login  SITE=__SITE__
```

Site URL: `http://__SITE__.islandora.io` (or https when the stack runs with `URI_SCHEME=https`).
Files are never part of a handover: at first start every `file_managed` row is re-pointed to
a generic file of its media type (`SITE_PLACEHOLDERS=relink`). Production accounts are never
used either: their rows are dropped from the normalized dump and the Lite dev site's accounts
are copied in (log in as `admin` with `secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD`).
