# ISLE: Site Template <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)

- [Introduction](#introduction)
  - [Forking Warning](#forking-warning)
  - [Assumptions](#assumptions)
- [Requirements](#requirements)
- [Automatic Setup](#automatic-setup)
- [Manual Setup](#manual-setup)
  - [Create a new repository](#create-a-new-repository)
  - [Setup Islandora Starter Site](#setup-islandora-starter-site)
- [Customizations](#customizations)
  - [Set environment properties](#set-environment-properties)
  - [Replace README.md with Template](#replace-readmemd-with-template)
- [Next Steps](#next-steps)

# Introduction

Template for building and customizing your institution's Islandora installation,
for use as both a development and production environment for your institution.

After confirming that [assumptions](#assumptions) match your use case, and you
have the appropriate [requirements
](#requirements), follow the
[instructions](#instructions) to set up your institution's Islandora
installation from this template.

> N.B. This is the **not** the only way to manage your Islandora installation,
> please also see [isle-dc] and [islandora-playbook], and consult with the wider
> community on the [Islandora Slack].

## Forking Warning

This is not intended to be an upstream fork that your institution will be
pulling changes from. Instead this repository acts as a template. The
intention is to make a new Git repository from it by copying the contents of
this repository into your institution's Git repository, for which your
institution will then be responsible.

This is for a few reasons. Primarily, we can't guarantee forward compatibility
with the changes made by your institution to a fork of this Git repository.
Your institution must be responsible for it's own configuration, as changes to
configuration **cannot** easily be shared across Drupal sites.

## Assumptions

This template assumes you'll be running your site in Docker
on a **single server**. If that is not your intention you may want to ask
in the Islandora Slack about existing examples for your chosen infrastructure.

This template is set up for a single site installation and isn't configured for a
[Drupal multisite](https://www.drupal.org/docs/multisite-drupal). It is possible
to add the functionality for that later, but it is left to the implementer to do
those additional changes.

While Islandora can be setup to use a wide variety of databases, tools and
configurations this template is set up for the following.

 - `blazegraph` is included by default.
 - `crayfish` services are included by default.
 - `fcrepo` is included by default.
 - `fits` is included by default.
 - `mariadb` is used for the backend database (rather than `postgresql`).
 - `solr` is included by default.
 - etc.

> N.B. Although alternate components and configurations are supported by
> Islandora, for simplicities sake the most common use-case is shown. For
> example `mariadb` is used rather than `postgresql`.

See the [customizations](#customizations) steps afterwards about removing unwanted features.

# Requirements

- [Docker 24.0+](https://docs.docker.com/get-docker/) **Referring to the Docker Engine version, not Docker Desktop**.
- [Docker Compose](https://docs.docker.com/compose/install/linux/) **Already included in OSX with Docker**
- [mkcert 1.4+](https://github.com/FiloSottile/mkcert)
- `cURL` and `git`
## Java and macOS

mkcert seems to have problems when running on Java installed via Homebrew. 
This is resolved by installing OpenJDK from an installer such as [temurin](https://adoptium.net/temurin/releases/) from the Eclipse foundation.

Be sure to set the JAVA_HOME environment variable to the correct
 value, for version 20 of the temurin packaged installer linked above it is: 

```
/Library/Java/JavaVirtualMachines/temurin-20.jdk/Contents/Home
```


# Automatic Setup

After installing the [requirements](#requirements), run the following command
for an automated setup. It is roughly equivalent to the
[Manual Setup](#manual-setup).

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Islandora-Devops/isle-site-template/main/setup.sh)"
```

You should now have a folder with the `SITE_NAME` you provided to the above
script with the basics completed for you.

On your platform of choice ([GitHub], [GitLab], etc), create a new Git repository
for your new site. This step allows you to persist your customizations to this
repository. It is not necessary for a throwaway development instance. 

In the following sections the [GitHub], [GitLab], etc; organization will be
referred to as `INSTITUTION`, and the Git repository will be referred to as
`SITE_NAME`.

Push the automatically generated repository to your remote (*For example with [GitHub]*):

```bash
cd SITE-NAME
git remote add origin git@github.com:INSTITUTION/SITE-NAME.git
git push
```

You can now continue on to [customizations](#customizations).

# Manual Setup

## Create a new repository

On your platform of choice [GitHub], [GitLab], etc. Create a new Git repository
for your new site. Having these files in Git will make future steps possible.

In the following sections the [GitHub], [GitLab], etc; organization will be
referred to as `INSTITUTION`, and the Git repository will be referred to as
`SITE_NAME`.

1. Clone a copy locally (*For example with [GitHub]*):

```bash
git clone git@github.com:INSTITUTION/SITE-NAME.git
cd SITE-NAME
```

At this point it should be an empty folder.

2. Unpack this repository into that empty folder, using the `main` branch (or the latest
   release, if you [alter what comes after `refs`](https://docs.github.com/en/repositories/working-with-files/using-files/downloading-source-code-archives#source-code-archive-urls)).

```bash
curl -L https://github.com/Islandora-Devops/isle-site-template/archive/refs/heads/main.tar.gz | tar -xz --strip-components=1
```

3. Remove .github folder and setup.sh

```bash
rm -fr .github setup.sh
```

4. Create the first commit:

```bash
git add .
git commit -am "First commit, added isle-site-template."
```

5. Push your changes to your institution's repository:

```bash
git push
```

## Setup Islandora Starter Site

Just as this repository is not intended to be an upstream fork, neither is the
[islandora-starter-site]. It is a starting point from which your institution
will customize and manage Drupal for your Islandora installation.

1. Unpack the [islandora-starter-site] using the `main` branch (or the latest
   release, if you alter what comes after `refs`).
   Run this command from the root of your repository.

```bash
curl -L https://github.com/Islandora-Devops/islandora-starter-site/archive/refs/heads/main.tar.gz \
    | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
```

This will place the contents in [drupal/rootfs/var/www/drupal].

2. Remove unneeded files (from the root of your repository):

```bash
rm -fr \
  drupal/rootfs/var/www/drupal/.github
```

3. Revert the content of
   [drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt] to what
   was originally there.

```bash
git checkout drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt
```

3. Create the second commit:

```bash
git add .
git commit -am "Second commit, added islandora-starter-site."
```

4. Push your changes to your institution's repository:

```bash
git push
```

5. Create a custom `.env` file from the provided sample:

```bash
cp sample.env .env
```

6. For a development server, generate certs and secrets.
```bash
./generate-certs.sh
./generate-secrets.sh
```

Continue on to [Customizations](#customizations).

# Customizations

The previous sections will have set you up with a Git repository to start from,
but more customization is likely needed.

Read through each following sections and follow the steps if you deem them
applicable to your institution's situation.

## Set environment properties

Edit [.env] and replace the following line with a name derived from your site
name. If you have multiple sites on the same host, these must be unique.

```bash
COMPOSE_PROJECT_NAME=isle-site-template
```

`ISLANDORA_TAG` tells Docker what version of [Isle Buildkit](https://github.com/Islandora-Devops/isle-buildkit) 
to use for the images. You should set this to the most 
[recent release](https://github.com/Islandora-Devops/isle-buildkit/releases) number, 
unless you have a reason to use older images.

> [!WARNING]
> You should not use `ISLANDORA_TAG=main` in production.

If setting up your own images on a remote Docker image registry like [DockerHub],
set the following line to your use your image registry:

```bash
# The Docker image repository, to push/pull custom images from.
# islandora.io redirects to localhost.
REPOSITORY=islandora.io
```

If using a purchased a domain name for your production site, set the following line
to your new domain:

```bash
# The domain at which your production site is hosted.
DOMAIN=islandora.dev
```
Lastly update the default email to that of your site's administrator:

```bash
# The email to use for admin users and Lets Encrypt.
EMAIL=postmaster@example.com
```

> N.B. This is required to property generate certificates automatically!

## Replace README.md with Template

Since this `README.md` is meant as a guide for creating your institution's
Islandora installation, it is not useful after that point. Instead a template
[README.template.md](./README.template.md) is provided from which you can then
customize. This template includes instructions on how to build and start up your
containers, as well as how to customize your Islandora installation. Please read
it after completing the steps in this `README.md`.

1. Replace this README.md with the template:

```bash
mv README.template.md README.md
```

2. Customize the README.md:

Replace instances of `INSTITUTION` and `SITE-NAME` with appropriate values and
add any additional information you see fit.

3. Commit your changes:

```bash
git commit -am "Replaced README.md from provided template."
```

4. Push your changes to your institution's repository:

```bash
git push
```
# Next Steps

Follow the rest of the instructions for setting up Islandora in
[README.md](./README.template.md) (formerly README.template.md).

[.env]: .env
[DockerHub]: https://hub.docker.com/
[drupal/rootfs/var/www/drupal]: drupal/rootfs/var/www/drupal
[drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt]: drupal/rootfs/var/www/drupal/assets/patches/default_settings.txt
[GitHub]: https://github.com/
[GitLab]: https://gitlab.com/
[Islandora Slack]: https://islandora.slack.com/
[islandora-playbook]: https://github.com/Islandora-Devops/islandora-playbook
[islandora-starter-site]: https://github.com/Islandora-Devops/islandora-starter-site
[isle-dc]: https://github.com/Islandora-Devops/isle-dc
[lets-encrypt]: https://letsencrypt.org/
[mkcert]: https://github.com/FiloSottile/mkcert
