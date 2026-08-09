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

## Reusable CI

The reusable workflow at `.github/workflows/fresh-install.yml` starts the default stack and confirms it serves traffic. It defaults to `ubuntu-24.04`; callers can pass `runner-os` directly or through a matrix:

```yaml
jobs:
  fresh-install:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-22.04, ubuntu-24.04, windows-2022, windows-2025]
    uses: Islandora-Devops/isle-site-template/.github/workflows/fresh-install.yml@<full-commit-sha>
    with:
      runner-os: ${{ matrix.os }}
```

For repository-specific test steps, use the composite action at `.github/actions/setup`. It checks out requested `isle-site-template` and `islandora-starter-site` sources, installs the latest compatible sitectl package set (minimum 1.0.0) from the signed LibOps APT repository, starts the default stack with the requested BuildKit tag, and waits for `sitectl healthcheck` to pass. It supports X64 Ubuntu runners and Windows runners through Ubuntu 24.04 on WSL2.

Pin the action to a full commit SHA in downstream workflows. The action leaves the stack running and exposes `project-directory`, `context-name`, and `compose-project-name` outputs. On Windows, paths are absolute within WSL and follow-up shell steps must use `wsl-bash {0}`:

```yaml
- id: isle
  uses: Islandora-Devops/isle-site-template/.github/actions/setup@<full-commit-sha>
  with:
    buildkit-tag: main

- name: Run tests against Islandora
  shell: ${{ runner.os == 'Windows' && 'wsl-bash {0}' || 'bash' }}
  env:
    SITECTL_CONTEXT: ${{ steps.isle.outputs.context-name }}
  run: sitectl verify --context "$SITECTL_CONTEXT"

- name: Clean up
  if: ${{ always() }}
  shell: ${{ runner.os == 'Windows' && 'wsl-bash {0}' || 'bash' }}
  env:
    SITECTL_CONTEXT: ${{ steps.isle.outputs.context-name }}
  run: sitectl compose --context "$SITECTL_CONTEXT" down --volumes --remove-orphans
```

To test a template pull request, pass its fork and immutable head commit through `isle-site-template-owner`, `isle-site-template-repository`, and `isle-site-template-ref`. To test an `islandora-starter-site` pull request, use the corresponding `starter-site-*` inputs. Pull-request code controls Docker builds, so run these tests on ephemeral GitHub-hosted runners without secrets or write permissions.

The optional `drupal-module-owner`, `drupal-module-repository`, and `drupal-module-ref` inputs stage a module checkout and expose `drupal-module-directory`. Installing that checkout into the fresh site is intentionally deferred until sitectl's module-under-test workflow is available; reserving the source inputs now avoids changing the action interface later.

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
