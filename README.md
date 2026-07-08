# ISLE Site Template

This template creates an Islandora stack with Docker Compose. New installs and routine operations are managed by [`sitectl`](https://sitectl.libops.io/) and the [`sitectl-isle`](https://sitectl.libops.io/plugins/isle) plugin.

For a deployed example that consumes this template, see [`islandora-devops/sandbox`](https://github.com/Islandora-Devops/sandbox).

## Requirements

- Docker with the Compose v2 plugin.
- [`sitectl-isle`](https://sitectl.libops.io/install). Package-manager installs of `sitectl-isle` also install the core `sitectl` command and `sitectl-drupal`.

## Quick Start

Create a new site from the template:

```bash
sitectl create isle/default \
  --template-repo https://github.com/Islandora-Devops/isle-site-template \
  --path ./my-islandora-site \
  --type local \
  --checkout-source template \
  --default-context
```

Create or refresh a context for an existing checkout:

```bash
cd ./my-islandora-site
sitectl create isle/default \
  --path . \
  --type local \
  --checkout-source existing \
  --default-context \
  --yolo \
  --fcrepo on \
  --blazegraph on \
  --iiif cantaloupe \
  --iiif-topology disabled \
  --fits on \
  --crayfits on \
  --homarus on \
  --houdini on \
  --hypercube on \
  --mergepdf on \
  --ingress on \
  --mode http \
  --domain islandora.io \
  --bot-mitigation off \
  --dev-mode off
```

The default local site is served through Traefik at `http://islandora.io`.

## Operations

Run these from the generated checkout, or pass `--context <name>` when operating from elsewhere.

Start or update the stack:

```bash
sitectl compose up
```

Stop the stack:

```bash
sitectl compose down
```

Check runtime health, project configuration, and Islandora behavior:

```bash
sitectl healthcheck
sitectl validate
sitectl verify
```

Use `sitectl verify --demo-objects` only on disposable CI, preview, development, or staging sites because it creates demo content.

Inspect and change managed components:

```bash
sitectl component describe
sitectl set fcrepo on
sitectl set blazegraph on
sitectl set iiif cantaloupe
sitectl set iiif-topology disabled
sitectl converge
```

Configure ingress, TLS, trusted proxies, and upload timeouts through the core ingress component:

```bash
sitectl set ingress on --mode http --domain islandora.io
sitectl set ingress on --mode https-mkcert --domain islandora.io
sitectl set ingress on --mode https-letsencrypt --domain islandora.example.org --acme-email ops@example.org
sitectl set ingress on --trusted-ip 203.0.113.10/32 --max-upload-size 2G --upload-timeout 10m
sitectl converge
```

Enable Traefik bot mitigation:

```bash
sitectl set bot-mitigation on
sitectl converge
```

Run Drupal commands through the included Drupal plugin:

```bash
sitectl drupal drush cr
sitectl drupal login
```

## CI Setup Action

The reusable composite action at `.github/actions/setup` installs `sitectl-isle`, refreshes the Drupal codebase from a requested `islandora-starter-site` repository/ref, creates the local ISLE context with explicit default component choices and `--yolo`, starts the stack, and runs `sitectl healthcheck`.

Downstream workflows can test the current starter-site branch or fork by passing the repository owner, repository name, and ref:

```yaml
- uses: Islandora-Devops/isle-site-template/.github/actions/setup@main
  with:
    starter-site-owner: ${{ github.event.pull_request.head.repo.owner.login }}
    starter-site-repository: ${{ github.event.pull_request.head.repo.name }}
    starter-site-ref: ${{ github.event.pull_request.head.sha }}
```

Use the action's ingress inputs when a test suite needs HTTPS. Workflows should not call the old Traefik helper scripts directly.

## Template Maintenance

The Makefile intentionally keeps only template maintenance targets that are not core sitectl operations:

```bash
make overwrite-starter-site
make sync-solr-conf
make create-starter-site-pr
```

Normal install, compose, validation, verification, ingress, and bot-mitigation workflows should use `sitectl`.

## Configuration Notes

`sitectl create isle/default` writes Compose and Drupal configuration for selected components. Review generated changes through version control before promoting them.

The `.env` file is generated from `sample.env` during initialization for Compose defaults such as image tags. Prefer `sitectl set ...` for managed runtime behavior instead of editing helper-specific environment variables.
