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

# Introduction

Template for building and customizing your institution's Islandora installation,
for use as both a development and production environment for your institution.

After confirming that [assumptions](#assumptions) match your use case, and you
have the appropriate [requirements](#requirements), follow the
[instructions](#instructions) to set up your institution's Islandora
installation from this template.

> N.B. This is the **not** the only way to manage your Islandora installation,
> please also see [isle-dc] and [islandora-playbook], and consult with the wider
> community on the [Islandora Slack].

## Forking Warning

This is not intended to be an upstream fork that your institution will be
pulling changes from. Instead this repository acts as a template, where the
intention is to make a new Git repository from it. By copying the contents of
this repository into your institution's Git repository. For which your
institution will then be responsible for.

This is for a few reasons. Namely, we can't guarantee forward compatibility with
the changes made by your institution to a fork of this Git repository. Your
institution must be responsible for it's own configuration, as changes to
configuration **cannot** easily be shared across Drupal sites.

## Assumptions

This template assumes you'll be using `docker compose` for running your site in
production on a **single server**. If that is not your intention you may want to ask
in the community slack about existing examples for your chosen infrastructure.

This template assumes a single site installation and isn't configured for a
[Drupal multisite](https://www.drupal.org/docs/multisite-drupal). It is possible
to add the functionality for that later, but it is left to the implementer to do
those additional changes.

While Islandora can be setup to use a wide variety of databases, tools and
configurations this template is limited to the following.

 - `blazegraph` is included by default.
 - `crayfish` services are included by default.
 - `fcrepo` is included by default.
 - `fits` is included by default.
 - `mariadb` is used for the backend database (rather than `postgresql`).
 - `matomo` is included by default.
 - `solr` is included by default.
 - etc.

> N.B. Although alternate components and configurations are supported by
> Islandora, for simplicities sake the most common use-case is shown. For
> example `mariadb` is used rather than `postgresql` is provided by this
> repository.

See the [customizations](#customizations) steps afterwards about removing unwanted features.

# Requirements

- [Docker 20.10+](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/linux/) **Already included in OSX with Docker**
- [mkcert 1.4+](https://github.com/FiloSottile/mkcert)

# Automatic Setup

After installing the [requirements](#requirements), run the following command
for an automated setup, it is roughly equivalent to the
[Manual Setup](#manual-setup).

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Islandora-Devops/isle-site-template/main/setup.sh)"
```

You should now have a folder with the `SITE_NAME` you provided to the above
script with the basics completed for you.

On your platform of choice [GitHub], [GitLab], etc. Create a new Git repository
for your new site.

In the following sections the [GitHub], [GitLab], etc; organization will be
referred to as `INSTITUTION`, and the Git repository will be referred to as
`SITE_NAME`.

Push the automatically generate repository to your remote (*For example with [GitHub]*):

```bash
cd SITE-NAME
git remote add origin git@github.com:INSTITUTION/SITE-NAME.git
git push
```

You can now continue on to [customizations](#customizations).

# Manual Setup

## Create a new repository

On your platform of choice [GitHub], [GitLab], etc. Create a new Git repository
for your new site.

In the following sections the [GitHub], [GitLab], etc; organization will be
referred to as `INSTITUTION`, and the Git repository will be referred to as
`SITE_NAME`.

1. Clone a copy locally (*For example with [GitHub]*):

```bash
git clone git@github.com:INSTITUTION/SITE-NAME.git
cd SITE-NAME
```

At this point it should be an empty folder.

2. Unpack this repository into that empty folder (using the latest release, or
   the `main` branch).

```bash
wget -c https://github.com/Islandora-Devops/isle-site-template/archive/refs/heads/main.tar.gz -O - | tar -xz --strip-components=1
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
will customize and manage your Islandora installation.

1. Unpack the [islandora-starter-site] using the latest release, or the `main`
   branch (from the root of your repository).

```bash
wget -c https://github.com/Islandora-Devops/islandora-starter-site/archive/refs/heads/main.tar.gz \
     -O - | tar --strip-components=1 -C drupal/rootfs/var/www/drupal -xz
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
git commit -am "Second commit, added isle-starter-site."
```

4. Push your changes to your institution's repository:

```bash
git push
```

Continue on to [Customizations](#customizations).

# Customizations

The previous sections will have set you up with a Git repository to start from,
but more customization is likely needed.

Read through each following sections and follow the steps if you deem them
applicable to your institutions situation.

## Set environment properties

Edit [.env] and replace the following line, with a name derived from your site
name:

```bash
COMPOSE_PROJECT_NAME=isle-site-template
```

After setting up a remote Docker image registry like [DockerHub]. Set the
following line to your use your image registry:

```bash
# The Docker image repository, to push/pull custom images from.
# islandora.io redirects to localhost.
REPOSITORY=islandora.io
```

After purchasing a domain name for your production site, set the following line
to your new domain:

```bash
# The domain at which your production site is hosted.
DOMAIN=islandora.dev
```
Lastly update the default email to that of your sites administrator:

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
