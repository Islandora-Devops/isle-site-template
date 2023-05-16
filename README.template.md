# SITE_NAME <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Docker Compose](#docker-compose)
  - [Override](#override)
  - [Building](#building)
  - [Pulling](#pulling)
  - [Running / Stoping / Destroying](#running--stoping--destroying)
    - [Development Profile](#development-profile)
    - [Production Profile](#production-profile)
  - [Pushing](#pushing)
    - [Local Registry](#local-registry)
    - [Remote Registry](#remote-registry)
- [Development](#development)
  - [UID](#uid)
  - [Development Certificates](#development-certificates)
    - [Create Certificate Authority](#create-certificate-authority)
      - [Windows](#windows)
      - [OSX and Linux](#osx-and-linux)
    - [Copy Certificate Authority files](#copy-certificate-authority-files)
      - [Windows](#windows-1)
      - [OSX and Linux](#osx-and-linux-1)
    - [Create Development Certificates](#create-development-certificates)
      - [Windows](#windows-2)
      - [OSX and Linux](#osx-and-linux-2)
  - [Upgrading Isle Docker Images](#upgrading-isle-docker-images)
  - [Drupal Development](#drupal-development)
- [Production](#production)
  - [Generate secrets](#generate-secrets)
  - [Production Domain](#production-domain)
  - [Automated Certificate Generation](#automated-certificate-generation)
  - [Setup as a systemd Service](#setup-as-a-systemd-service)
  - [SELinux Considerations](#selinux-considerations)

# Introduction

This is the development and production infrastructure for INSTITUTION's SITE_NAME.

# Requirements

- [Docker 20.10+](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/linux/) **Already included in OSX with Docker**
- [mkcert 1.4+](https://github.com/FiloSottile/mkcert) **Local Development only**

# Docker Compose

There are a number of `docker-compose.yml` files provided by this repository:

| File                                                       | Description                                                                                      |
| :--------------------------------------------------------- | :----------------------------------------------------------------------------------------------- |
| [docker-compose.yml](docker-compose.yml)                   | Defines all development & production services.                                                   |
| [docker-compose.darwin.yml](docker-compose.darwin.yml)     | Platform specific customizations to allow access to host `SSH_AGENT`. For development use only.  |
| [docker-compose.linux.yml](docker-compose.linux.yml)       | Platform specific customizations to allow access to host `SSH_AGENT`. For development use only.  |
| [docker-compose.override.yml](docker-compose.override.yml) | Customizations for local development environment.                                                |
| [docker-compose.registry.yml](docker-compose.registry.yml) | Used for creating a local registry for testing multi-arch builds, etc. Can typically be ignored. |

## Override

This repository ignores `docker-compose.override.yml` which will be included in
any `docker compose` commands you invoke by default.

Two platform dependent templates that allow for access to the hosts `SSH agent`
are provided for `development` environments.

Simply copy the appropriate `docker-compose.PLATFORM.yml` file into
`docker-compose.override.yml`, on your development machine.

Any additional changes that are for your local / development environment can
then be added to `docker-compose.override.yml`.

## Building

You can build your locally using `docker compose`

```bash
docker compose --profile dev build
```

## Pulling

The `docker compose` file provided require that you first pull the islandora
images with the following command:

```bash
docker compose --profile dev --profile prod pull --ignore-buildable --ignore-pull-failures
```

## Running / Stoping / Destroying

You must specify a profile either `dev` or `prod` to use `docker compose` files
provided by this repository.

### Development Profile

Use the `dev` profile when bring up your local/development environment:

```bash
docker compose --profile dev up -d
```

You must wait several minutes for the islandora site to install. When completed
you can see the following in the output from the `drupal-dev` container, with
the following command:

```bash
docker compose logs -f drupal-dev
```

```txt
#####################
# Install Completed #
#####################
```

For all accounts in the development profile the username and password is set to
the following:

| Credentials | Value    |
| :---------- | :------- |
| Username    | admin    |
| Password    | password |

If you have the domain in your `.env` set to `islandora.dev` you can access all
the services at the following URLs.

| Service    | URL                                       |
| :--------- | :---------------------------------------- |
| Drupal     | https://islandora.dev                     |
| IDE        | https://ide.islandora.dev                 |
| ActiveMQ   | https://activemq.islandora.dev            |
| Blazegraph | https://blazegraph.islandora.dev/bigdata/ |
| Fedora     | https://fcrepo.islandora.dev/fcrepo/rest/ |
| Matomo     | https://islandora.dev/matomo/index.php    |
| Solr       | https://solr.islandora.dev                |
| Traefik    | https://traefik.islandora.dev             |

To stop your local/development environment:

```bash
docker compose --profile dev down
```

To **destroy all data** from your local/development environment:

```bash
docker compose --profile dev down -v
```

### Production Profile

Use the `prod` profile when bring up your production environment:

```bash
docker compose --profile prod up -d
```

To stop your production environment:

```bash
docker compose --profile prod down
```

> N.B. You shouldn't really ever run the following on your production server.
> This is just when testing the differences for production environment on your
> local machine.

To **destroy all data** from your production environment:

```bash
docker compose --profile prod down -v
```

## Pushing

Pushing requires setting up either a [Local Registry](#local-registry), or a
[Remote Registry](#remote-registry). Though you may want to use both concurrently.

Additionally the command to build & push changes if you need multi-platform
support, i.e. if you need to be able to run on ARM (Apple M1, etc) as well as
x86 (Intel / AMD) CPUs.

### Local Registry

To test multi-platform builds locally requires setting up a local registry.

This can be done with the assistance of [isle-builder] repository.

> N.B. Alternatively you can push directly to a remote registry like
> [DockerHub], though that can be slow as it needs to upload your image over the
> network.

Now you can perform the build locally by pushing to the local registry:

```bash
REPOSITORY=islandora.io docker buildx bake --builder isle-builder --push
```

> N.B. If you **do not** override `REPOSITORY` environment variable, the value
> provided by [.env] is used, which will typically be the remote registry you
> intended to use.

### Remote Registry

First you must choose a Docker image registry provider such as [DockerHub].

Assuming your are logged into your remote repository, i.e. you've done
`docker login` with the appropriate arguments and credentials for your chosen
remote Docker image repository.

You must then replace the following line in [.env] to match the repository you
have created with your chosen registry provider:

```bash
# The Docker image repository, to push/pull custom images from.
# islandora.io redirects to localhost.
REPOSITORY=islandora.io
```

If you do not need to build multi-platform images, you can then push to the
remote repository using `docker compose`:

```bash
docker compose --profile dev push drupal-dev
```

If you do need produce multi-platform images, you'll need to setup a builder
which is covered under the [Local Registry](#local-registry) section.

```bash
docker buildx bake --builder isle-builder --push
```

> N.B. In this example `REPOSITORY` **is not** overridden, so the value provided
> by [.env] is used.

# Development

## UID

Use the following `bash` snippet to generate the `./certs/UID` file.

```bash
printf '%s' "$(id -u)" > ./certs/UID
```

This is used on container startup to make sure bind mounted files are owned by
the same user as the host machine.

> N.B. Alternatively this file is generated when you run [generate-certs.sh]

## Development Certificates

If you have [mkcert] properly installed you can simply run [generate-certs.sh]
to generate development certificates, otherwise follow the manual steps outlined
below.

Before we can start a local instance of the site we must generate certificates
for local development. This varies a bit across platforms, please refer to the
[mkcert] documentation to ensure your setup is correct for your host platform,
and you have the appropriate dependencies installed.

> These certificates are only used for local development production is setup to use
> certificates automatically generated by [lets-encrypt].

### Create Certificate Authority

> N.B. This only has to be done **once** per host, and is only required for
> **local development**. On a production server you should be using actual
> certificates which will be documented in a later section.

#### Windows

You must do this using `cmd.exe` as an **Administrator** as `WSL` does **not**
have access to Windows trust store and is not able to install certificates.

1. Generate and install `rootCA` files:

```bat
mkcert.exe -install
```

#### OSX and Linux

1. Generate and install `rootCA` files:

```bash
mkcert -install
```

### Copy Certificate Authority files

The previous step generate two rootCA files which you must copy into this repositories
[certs](./certs/) folder.

#### Windows

Using `cmd.exe` although no longer as an administrator.

1. Determine the location  of the `rootCA` files:

```bat
mkcert.exe -CAROOT
```

2. Copy the certificates into the [certs](./certs) folder (from the root of your repository):

```
set CAROOT="VALUE FROM STEP #1"
copy %CAROOT%\rootCA-key.pem certs
copy %CAROOT%\rootCA.pem certs
```

> N.B. Firefox does not work with these certificates on Windows. So you must use
> either Chrome or Edge on Windows.

#### OSX and Linux

```bash
cp $(mkcert -CAROOT)/* certs/
```

### Create Development Certificates

#### Windows

Using `cmd.exe` although no longer as an administrator.

1. Create site certificates (from the root of your repository):

```bat
mkcert.exe -cert-file certs\cert.pem -key-file certs\privkey.pem "*.islandora.dev" "islandora.dev" "*.islandora.io" "islandora.io" "*.islandora.info" "islandora.info" "localhost" "127.0.0.1" "::1"
```

#### OSX and Linux

1. Create site certificates (from the root of your repository):

```bash
mkcert \
  -cert-file certs/cert.pem \
  -key-file certs/privkey.pem \
  "*.islandora.dev" \
  "islandora.dev" \
  "*.islandora.io" \
  "islandora.io" \
  "*.islandora.info" \
  "islandora.info" \
  "localhost" \
  "127.0.0.1" \
  "::1"
```

## Upgrading Isle Docker Images

Edit [.env] and replace the following line, with your new targeted version:

```bash
# The version of the isle-buildkit images to use.
ISLANDORA_TAG=x.x.x
```

Then you can [pull](#pulling) the latest images as described previously.

Then read the **release notes** for the versions between your current version
and your target version, as manual steps beyond what is listed here will likely
be required.

Of course **make backups** before deploying to production and test thoroughly.

## Drupal Development

For local development via the [development profile], an [IDE] is provided which
can also support the use of [PHPStorm].

There are a number of bind mounted directories so changes made in the following
files & folders will persist in this Git repository.

- /var/www/drupal/assets
- /var/www/drupal/composer.json
- /var/www/drupal/composer.lock
- /var/www/drupal/config
- /var/www/drupal/web/modules/custom
- /var/www/drupal/web/themes/custom

Other changes such as to the `vendor` folder or installed modules are **not**
persisted, to disk. This is by design as these changes should be managed via
`composer` and baked into the Drupal Docker image.

Changes made to `composer.json` and `composer.lock` will require you to rebuild
the Drupal Docker image, see [building](#building) for how.

> N.B. None of the above directories are bind mounted in production as
> development in a production environment is not supported. The production site
> should be fairly locked down, and only permit changes to content and not
> configuration.

# Production

Running in production makes use of the [production profile], which requires
either manually provided secrets, or generating secrets. As well as a properly
configured DNS records as is described in the following sections.

## Generate secrets

To be able to run the production profile of the [docker-compose.yml] file the
referenced secrets and JWT public/private key pair must be created. There is
inline instructions for generating each secret in [docker-compose.yml].

Alternatively you can use the [generate-secrets.sh] `bash` script to generate
them all quickly.

> N.B. The script will not overwrite existing secret files so it's safe to run
> repeatedly.

## Production Domain

The [.env] has a variable `DOMAIN` which should be set to the production sites
domain.

```bash
# The domain at which your production site is hosted.
DOMAIN=xxx.xxx
```

## Automated Certificate Generation

Traefik has support for [acme] (_Automatic Certificate Management Environment_).
This is what is used to generate certificates in a production environment.

This is configured to use a HTTP based challenge and requires that the following
`A Records` be set in your production sites `DNS Records`. Where `DOMAIN` is
replaced with the production sites domain.

- ${DOMAIN}
- activemq.${DOMAIN}
- blazegraph.${DOMAIN}
- fcrepo.${DOMAIN}
- solr.${DOMAIN}

Each of the above values should be set to the IP address of your production
server.

Additionally be sure to update the default email to that of your sites
administrator:

```bash
# The email to use for admin users and Lets Encrypt.
EMAIL=postmaster@example.com
```

> N.B. This is required to property generate certificates automatically!

## Setup as a systemd Service

Most Linux distributions use `systemd` for process management, on your production
server you can use the following unit file with `systemd`.

> N.B. Replace the `User`, `Group`, and `WorkingDirectory` lines as appropriate.

```ini
[Unit]
Description= Islandora
PartOf=docker.service
After=docker.service

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/SITE_NAME
ExecStart=/usr/bin/docker compose --profile prod up
ExecStop=/usr/bin/docker compose --profile prod down

[Install]
WantedBy=multi-user.target
```

## SELinux Considerations

If you using a system with SELinux enabled, you will need to set the appropriate
labels on the generated secrets files for Docker to be allowed to mount them
into containers.

```bash
sudo chcon -R -t container_file_t secrets/*
```

[.env]: .env
[acme]: https://doc.traefik.io/traefik/https/acme/
[development profile]: #development-profile
[docker-compose.yml]: ./docker-compose.yml
[DockerHub]: https://hub.docker.com/
[generate-certs.sh]: ./generate-certs.sh
[generate-secrets.sh]: ./generate-secrets.sh
[IDE]: https://github.com/Islandora-Devops/isle-buildkit#ide
[isle-builder]: https://github.com/Islandora-Devops/isle-builder
[lets-encrypt]: https://letsencrypt.org/
[mkcert]: https://github.com/FiloSottile/mkcert
[PHPStorm]: https://github.com/Islandora-Devops/isle-buildkit#phpstorm
[production profile]: #production-profile