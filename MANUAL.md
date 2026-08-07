# isle-sitectl Manual

A concise operator's guide to this ISLE / Islandora site stack. Everything is driven by
`make` targets that wrap `docker compose` and the helper scripts in `scripts/`.

For background and upstream detail, see [README.md](./README.md).

## 1. Prerequisites

- Docker 24.0+ with Docker Compose
- `make`, `curl`, `git`
- `mkcert` (only for local HTTPS)
- `yq` (used by secret generation)
- Run all commands from the repository root.

## 2. First run

```bash
make up
```

That single command will, as needed:

1. Create `.env` from `sample.env` (via `scripts/init.sh`).
2. Generate secrets into `secrets/` and certificates into `certs/`.
3. Build the `drupal` image.
4. Start the stack with automatic port fallback (80 → 8080, 443 → 8443 if busy).
5. Tail the Drupal install log until `Install Completed`, then print the site URL and open a browser.

The first run takes several minutes while Drupal installs. Default URL: <http://islandora.io>
(`islandora.io` resolves to `127.0.0.1`).

**Login:** user `admin`, password from `cat ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD`.

## 3. Command reference

Run `make help` for the live list. Core targets:

| Target | What it does |
| :--- | :--- |
| `make up` | Start everything with smart port allocation (`scripts/up.sh`) |
| `make down` | Stop and remove containers + network |
| `make build` | Pull base images, then build the `drupal` image |
| `make init` | Prepare the host: `.env`, secrets, certs, then build |
| `make status` | Report config problems and Traefik/TLS state |
| `make ping` | Poll the site until it responds with Islandora content |
| `make clean` | **Destructive.** Prompts, then removes volumes, `certs/*`, `secrets/*`, `.env` |
| `make demo-objects` | Ingest [islandora_demo_objects] via Islandora Workbench |
| `make sync-solr-conf` | Refresh tracked Solr core config from the running `drupal` container |
| `make overwrite-starter-site` | Re-sync `drupal/rootfs/var/www/drupal` from `islandora-starter-site` |
| `make create-starter-site-pr` | Stage starter-site changes (opens a PR only in GitHub Actions) |
| `make sequelace` | Open the Drupal database in Sequel Ace (macOS) |

Pattern targets, where `%` is a compose service name:

| Target | Example |
| :--- | :--- |
| `make up-%` | `make up-drupal` |
| `make down-%` | `make down-traefik` |
| `make logs-%` | `make logs-drupal` (last 20 lines, follows) |

**Service names:** `activemq`, `alpaca`, `blazegraph`, `cantaloupe`, `crayfits`, `drupal`,
`fcrepo`, `fits`, `homarus`, `houdini`, `hypercube`, `init`, `mariadb`, `mergepdf`,
`milliner`, `solr`, `traefik`.

## 4. Configuration

All configuration lives in `.env` (untracked; created from `sample.env`). Key variables:

- `COMPOSE_PROJECT_NAME` — container/volume/network prefix. **Change this** from the default
  `isle-site-template` if you run more than one ISLE stack on a host.
- `DOMAIN` — site domain (default `islandora.io`).
- `URI_SCHEME` — `http` or `https`.
- `TLS_PROVIDER` — `self-managed` or `letsencrypt`.
- `ACME_EMAIL` / `ACME_URL` — Let's Encrypt contact and directory endpoint (swap in the
  staging URL while testing).
- `DEVELOPMENT_ENVIRONMENT` — `true` remaps container UIDs and enables port fallback.
  **Never `true` on a publicly reachable site.**
- `ISLANDORA_TAG` — [isle-buildkit] image version.
- `REPOSITORY` / `TAG` — registry and tag for custom images.
- `REVERSE_PROXY` + `FRONTEND_IP_*` — set when the stack sits behind another proxy so Drupal
  sees real client IPs.

Prefer the `traefik-*` targets over hand-editing TLS values; they rewrite both `.env` and
`docker-compose.yml` consistently.

## 5. Service URLs

With `DOMAIN=islandora.io` and `URI_SCHEME=http`:

| Service | URL |
| :--- | :--- |
| Drupal | <http://islandora.io> |
| ActiveMQ | <http://activemq.islandora.io> |
| Blazegraph | <http://blazegraph.islandora.io/bigdata/> |
| Cantaloupe | <http://islandora.io/cantaloupe> |
| Fedora | <http://fcrepo.islandora.io/fcrepo/rest/> |
| Solr | <http://solr.islandora.io> |
| Traefik | <http://traefik.islandora.io> |

If port 80/443 was already taken, append the port shown in the `make up` output.

## 6. HTTP / HTTPS modes

Each switch requires a Traefik restart to take effect:

```bash
make traefik-http                 # plain HTTP (default)
make traefik-https-mkcert         # local trusted certs via mkcert (macOS/Linux; not WSL)
make traefik-https-letsencrypt    # prompts for domain + email, sets production mode
make down-traefik up              # apply the change
```

`make traefik-https-letsencrypt` also sets `DEVELOPMENT_ENVIRONMENT=false`. Point DNS A
records for `${DOMAIN}` and `fcrepo.${DOMAIN}` at the server before running it.

## 7. Development workflow

Enable the dev override once so your local Drupal codebase is bind-mounted into the
container (and MariaDB is exposed on 3306):

```bash
ln -s docker-compose.dev.yml docker-compose.override.yml
make up
```

`docker-compose.override.yml` is untracked, so local-only tweaks belong there. For multiple
environments, commit `docker-compose.dev.yml` / `.stage.yml` / `.prod.yml` and symlink the
right one as `docker-compose.override.yml` on each host.

Changes that persist to git live under `drupal/rootfs/var/www/drupal/`:
`assets/`, `config/`, `web/modules/custom/`, `web/themes/custom/`, and top-level files.

Common in-container operations:

```bash
docker compose exec drupal composer require drupal/module
docker compose exec drupal drush cr
docker compose exec drupal drush config:export
```

After changing Solr-affecting Drupal config, run `make sync-solr-conf` to refresh the
tracked core config.

Add your own targets in `custom.Makefile` (untracked-friendly, auto-included). Custom
targets cannot override targets already defined in `Makefile`.

## 8. Production notes

1. Set a unique `COMPOSE_PROJECT_NAME`, a real `DOMAIN`, `DEVELOPMENT_ENVIRONMENT=false`.
2. Enable TLS with `make traefik-https-letsencrypt`, then `make down-traefik up`.
3. Back up `secrets/` — losing `DRUPAL_DEFAULT_SALT` or the JWT keypair breaks the site.
4. Manage the stack with systemd (unit file example in the README) so it restarts on boot.
5. Build and publish custom images:
   ```bash
   docker compose push drupal                                   # single platform
   docker buildx bake --pull --builder isle-builder --push       # multi-arch
   ```

## 9. Troubleshooting

- **Start with `make status`.** It flags rootless Docker under dev mode, a missing compose
  override, the default `COMPOSE_PROJECT_NAME`, missing or mismatched JWT keys, and
  TLS/scheme inconsistencies.
- **Site never comes up:** `make logs-drupal`, then `make logs-solr`. `drupal` depends on
  `solr`, so `up.sh` retries once by starting `solr` first.
- **Port already in use:** in dev mode ports shift automatically; check the URL printed by
  `make up`, or `docker compose port traefik 80`.
- **Is it live?** `make ping` (retries with backoff, fails after 10 attempts).
- **Rootless Docker:** unsupported with `DEVELOPMENT_ENVIRONMENT=true`; set it to `false`.
- **Windows:** use WSL 2. mkcert and Let's Encrypt targets refuse to run under WSL.
- **Start over:** `make clean` deletes all volumes, secrets, certs, and `.env`, then
  `make up` rebuilds from scratch.

[isle-buildkit]: https://github.com/Islandora-Devops/isle-buildkit
[islandora_demo_objects]: https://github.com/Islandora-Devops/islandora_demo_objects
