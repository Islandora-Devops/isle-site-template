# Production Cantaloupe config (`lite/cantaloupe/`)

One `cantaloupe` service serves the Lite dev site and every replica, so its config is a
manual input for the whole stack, not per site.

| Path | Provided by |
| --- | --- |
| `conf/` | you, optional (absent: a warning, the image's config applies): production's Cantaloupe config folder as is (`cantaloupe.properties` and, if it enables the delegate script, its one `*.rb`) |
| `stage/` | generated: `cantaloupe.env` (`CANTALOUPE_*` variables) and `delegates.rb` |

```bash
cp -R <production Cantaloupe config folder>/. lite/cantaloupe/conf/
make site-check  SITE=<site>     # validates it (step 6)
make site-intake SITE=<site>     # translates and test-starts it into stage/ (step 4)
make site-up     SITE=<site>     # recreates cantaloupe with it (or: make lite-cantaloupe)
```

`make lite-cantaloupe` does the same without a site. Both folders are git-ignored.

**What gets translated.** The `islandora/cantaloupe` image writes its `cantaloupe.properties`
from `CANTALOUPE_*` variables on every start, so editing that file in the container does not
last. `lite/intake/cantaloupe-conf.sh` turns each production property into its variable,
which `docker-compose.lite.yml` passes to the service as an optional `env_file`. Some values
keep the image's setting instead:
- **This container's own settings:** ports, paths, logs, binaries.
- **Production credentials and other storage:** the admin/API endpoints, JDBC, Redis, S3
  and Azure.
- **Values the image can't take:** empty values, values with a backslash escape, keys the
  image has no variable for, and processors this Cantaloupe doesn't have.

The delegate script gets two changes: its relative log paths move to `/tmp`, because the
process runs in the root-owned `/opt/cantaloupe`, and JRuby checks its syntax. A throwaway
Cantaloupe has to start with the result and run the delegate without errors. The report
lists every value it leaves out.
