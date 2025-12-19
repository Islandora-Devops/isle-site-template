![Asset 2](https://github.com/Islandora-Devops/islandora-starter-site/assets/467898/0c861461-8b7c-49ee-ab52-c371a1c2f7df)
# Islandora Starter Site

[![Minimum PHP Version](https://img.shields.io/badge/php-%3E%3D%207.4-8892BF.svg?style=flat-square)](https://php.net/)
[![Contribution Guidelines](http://img.shields.io/badge/CONTRIBUTING-Guidelines-blue.svg)](./CONTRIBUTING.md)
[![LICENSE](https://img.shields.io/badge/license-GPLv2-blue.svg?style=flat-square)](./LICENSE)

A starting Drupal configuration for Islandora sites. 

## What is a Starter Site?

The Starter Site is a ready-to-customize Drupal site that shows off Islandora's features. It can be used as a template for your site, but once you start using it, your site (and all its config) are managed by you. Like a template MS Word document, changes that are made to the template after you've started using it **cannot and will not** be automatically transferred into your copy (in this case, your Islandora site). If you need these kinds of services done for you, check out our [service providers](https://www.islandora.ca/service-providers). However, we will endeavour to document and communicate changes, should you wish to incorporate them.

The Starter site contains instructions to set up a Drupal site, but several features requre the presence of external services such as Fedora, Solr, and others (see installation instructions below). 

The Starter Site uses semantic-like versioning now, but this is only for compatibility with the tools that install it. The Starter Site will change major versions whenever it requires something new from the tools that create its environment (Playbook/ISLE).

## Quick Installation

To launch a fully-functioning Islandora Starter site as well as the (non-Drupal)
tools and services that support it, try one of the Islandora deployment tools:

* [Islandora Playbook](https://github.com/Islandora-Devops/islandora-playbook) - Ansible-based, works locally with VirtualBox and Vagrant.
  * use the `starter` (default) or `starter_dev` option
* [ISLE-DC](https://github.com/Islandora-Devops/isle-dc) - Docker-based
  * use the `make starter` or `make starter_dev` option
* [ISLE Site Template](https://github.com/Islandora-Devops/isle-site-template) - Docker-based
  * The default installation instructions use the Starter Site.

## Manual Installation

The config files in the Starter Site assume a full suite of external services.
If you do not need all the external services (such as Fedora) then
you can skip them but you will also want to adjust the Drupal configs. Such a
partial install is beyond the scope of this document.

## Prerequisites

1. PHP and [Composer](https://getcomposer.org/) installed
2. A Database server installed and [configured for Drupal](https://www.drupal.org/docs/system-requirements/database-server-requirements)
    * The Starter Site installs drivers for MySQL/MariaDB/Percona (`mysql`),
PostgreSQL (`pgsql`), and SQLite (`sqlite`). Using other (contrib) drivers
would require additional installation/configuration, and is outside the
scope of this document.
3. [Fedora Commons (FCRepo)](https://github.com/fcrepo/fcrepo) installed
    1. [Syn](https://github.com/Islandora/Syn/) installed and configured with a
key.
4. Triplestore installed
5. Cantaloupe installed
    1. A IIIF URL is expected to be resolvable, and to accept full URLs as
resource IDs. If the URL is not `http://127.0.0.1:8080/cantaloupe/iiif/2`,
this will have to be set (see Usage step 5).
6. ActiveMQ/Alpaca/Crayfish installation
    1. ActiveMQ expected to be listening for STOMP messages at a `tcp` url.
If not the default `tcp://127.0.0.1:61613`, this will have to be set (see Usage step 5)
    2. Queues (and underlying (micro)services) configured appropriately:

| Queue Name                                | Destination                                                |
|-------------------------------------------|------------------------------------------------------------|
| `islandora-connector-homarus`             | Homarus (Crayfish ffmpeg transcoding microservice)         |
| `islandora-indexing-fcrepo-delete`        | FCRepo indexer                                             |
| `islandora-indexing-triplestore-delete`   | Triplestore indexer                                        |
| `islandora-connector-houdini`             | Houdini (Crayfish imagemagick transformation microservice) |
| `islandora-connector-ocr`                 | Hypercube (Crayfish OCR microservice)                      |
| `islandora-indexing-fcrepo-file-external` | FCRepo indexer                                             |
| `islandora-indexing-fcrepo-media`         | FCRepo indexer                                             |
| `islandora-indexing-triplestore-index`    | Triplestore indexer                                        |
| `islandora-indexing-fcrepo-content`       | FCRepo indexer                                             |
| `islandora-connector-fits`                | CrayFits derivative processor                              |

7. A [Drupal-compatible web server](https://www.drupal.org/docs/system-requirements/web-server-requirements)
8. [FITS Web Service](https://projects.iq.harvard.edu/fits/downloads#fits-servlet) and
[CrayFits](https://github.com/roblib/CrayFits) installed
    * Further details in the [`islandora_fits` module's](https://github.com/roblib/islandora_fits) README/documentation
9. A Solr server installed or available with a core set up
    * Further details on [Drupal's Search API Solr module](https://www.drupal.org/project/search_api_solr) page.
    * If not available at `127.0.0.1:8983`, or if the core name is not `ISLANDORA` its information will need to be set up (see Usage step 5)

## Usage

1. Create a project based on this repository:

    ```bash
    composer create-project islandora/islandora-starter-site
    ```

    This should:
    1. Grab the code and all PHP dependencies,
    2. Scaffold the site, and have the `default` site's `settings.php` point at
      our included configuration for the next step.

2. Configure Flysystem's `fedora` scheme in the site's `settings.php`:

    ```php
    $settings['flysystem'] = [
      'fedora' => [
        'driver' => 'fedora',
        'config' => [
          'root' => 'http://127.0.0.1:8080/fcrepo/rest/',
        ],
      ],
    ];
    ```

    Changing `http://127.0.0.1:8080` to point at your Fedora installation.

3. Install the site:

    ```bash
    composer exec -- drush site:install --existing-config
    ```

    After this step, you should configure your web server to serve `web/`
directory as its document root.


4. Add (or otherwise create) a user to the `fedoraadmin` role; for example,
giving the default `admin` user the role:

    ```bash
    composer exec -- drush user:role:add fedoraadmin admin
    ```

5. Configure the locations of external services.

Change the following Drupal configs to your values using any method (GUI,
`drush cset`, config overrides in `settings.php`...):

| Value                           | Drupal Config item                    | Default Starter Site value                | 
| ------------------------------- | ------------------------------------- | ------------------------------------------|
| ActiveMQ (broker)               | `islandora.settings broker_url`       | `tcp://127.0.0.1:61613`                   |
| Cantaloupe (for OpenSeadragon)  | `openseadragon.settings iiif_server`  | `http://127.0.0.1:8080/cantaloupe/iiif/2` |
| Cantaloupe (for Islandora IIIF) | `islandora_iiif.settings iiif_server` | `http://127.0.0.1:8080/cantaloupe/iiif/2` |
| Solr - URL                      | `search_api.server.default_solr_server backend_config.connector_config.host` | `127.0.0.1` |
| Solr - port                     | `search_api.server.default_solr_server backend_config.connector_config.port` | `8983` |
| Solr - core name                | `search_api.server.default_solr_server backend_config.connector_config.core` | `ISLANDORA` |


6. Make the Syn/JWT keys available to our configuration either by (or by some combination of):
    1. Symlinking the private key to `/opt/islandora/auth/private.key`; or,
    2. Setting the appropriate location as `key.key.islandora_rsa_key key_provider_settings.file_location`
(using the methods listed in step 5 or at `/admin/config/system/keys/manage/islandora_rsa_key`)

7. Run the migrations tagged with `islandora` to populate some
taxonomies, specifying the `--userid` targeting the user with the `fedoraadmin`
role:

    ```bash
    composer exec -- drush migrate:import --userid=1 --tag=islandora
    ```


This should get you a starter Islandora site with:

* A basic node bundle to represent repository content
* A handful of media types that store content in Fedora
* RDF and JSON-LD mappings for miscellaneous entities to support storage in
Fedora, Triplestore indexing and client requests.

### Post-installation cleanup

1. Uninstall the database driver modules you are not using; for example, if
you are using `mysql` to use a MySQL-compatible database, you should be clear to
uninstall the `pgsql` (PostgreSQL) and `sqlite` (SQLite) modules:

    ```bash
    composer exec -- drush pm:uninstall pgsql sqlite
    ```

### Known issues

#### Warnings/errors during installation

Some modules presently have some bad expectations as to the system state when
`hook_install()` is invoked and as such, some messages are emitted:

```
$ composer exec -- drush site:install --existing-config --db-url=mysql://user:***@localhost/db

 You are about to:
 * DROP all tables in your 'db' database.

 Do you want to continue? (yes/no) [yes]:
 >

 [notice] Starting Drupal installation. This takes a while.
 [notice] Performed install task: install_select_language
 [notice] Performed install task: install_select_profile
 [notice] Performed install task: install_load_profile
 [notice] Performed install task: install_verify_requirements
 [notice] Performed install task: install_settings_form
 [notice] Performed install task: install_verify_database_ready
 [notice] Performed install task: install_base_system
 [notice] Performed install task: install_bootstrap_full
 [error]  The Flysystem driver is missing.
 [warning] Could not find required jsonld.settings to add default RDF namespaces.
 [notice] Performed install task: install_config_import_batch
 [notice] Performed install task: install_config_download_translations
 [notice] Performed install task: install_config_revert_install_changes
 [notice] Performed install task: install_configure_form
 [notice] Performed install task: install_finished
 [success] Installation complete.  User name: admin  User password: ***
$
```

There are two "unexpected" messages there:

* `[error]  The Flysystem driver is missing.`
    * Appears to be from [the `flysystem` module's `hook_install()` implementation](https://git.drupalcode.org/project/flysystem/-/blob/cf46f90fa6cda0e794318d04e5e8e6e148818c9a/flysystem.install#L27-32)
      where it tries to ensure that all schemes defined are in a state ready
      to be used; however, all the modules are not yet enabled (in the
      particular case, `islandora` is not actually enabled, so the `fedora` driver is unknown),
      and so leading to this message being emitted. The `islandora` module
      _is_ enabled by the time the command exits, so this message should be
      ignorable.
* `[warning] Could not find required jsonld.settings to add default RDF namespaces.`
    * Appears to be from [the `islandora` module's `hook_install()` implementation](https://github.com/Islandora/islandora/blob/725b5592803564c9727e920b780247e45ecbc9a4/islandora.install#L8-L13)
      where it tries to alter the `jsonld` module's `jsonld.settings` config
      object to add some namespaces; however, because the configs are not yet
      installed when installing the modules with `--existing-config`, it fails
      to find the target configuration to alter it. As exported, the
      `jsonld.settings` already contains the alterations (at time of writing),
      so this warning should be ignorable.

In summary: These two messages seem to be ignorable.

#### Patches

If a patch (external or internal) is necessary, it can be applied automatically by composer by using the [composer-patches plugin](https://github.com/cweagans/composer-patches). Any patches included in the Starter Site should be described fully in this section (including when they should be removed).

* None, presently.

### Ongoing Project Maintenance

It is anticipated that [Composer](https://getcomposer.org/) will be used to manage Drupal and its extensions,
including Islandora's suite of modules. The Drupal project has already documented many of the interactions in this
space, so we will just list and summarize them here:

[Using Composer to Install Drupal and Manage Dependencies](https://www.drupal.org/docs/develop/using-composer/manage-dependencies)
* The "install" describing:
    * Composer's `create-project` command, which we describe above being used to install
      using this "starter site" project; and,
    * The `drush site:install`/`drush si` command, described above being used to install Drupal via the command line.
* "manage[ment]", describing:
    * Composer's `require` command, used to add additional dependencies to your project
    * Updating, linking out to additional documentation for Drupal's core and modules:
        * [Updating Drupal core via Composer](https://www.drupal.org/docs/updating-drupal/updating-drupal-core-via-composer)
        * [Updating Modules and Themes using Composer](https://www.drupal.org/docs/updating-drupal/updating-modules-and-themes-using-composer)

    Generally, gets into using Composer's `update` command to update extensions according to the specifications in
    the `composer.json`, and Composer's `require` command to _change_ those specifications when necessary to cross
    major version boundaries.

It is also recommended to monitor and/or subscribe to Drupal's security advisories to know when it might be
necessary to update.

## Documentation

Further documentation for this ecosystem is available on the [Islandora documentation site](https://islandora.github.io/documentation/).

## Troubleshooting/Issues

Having problems or solved a problem? Check out the Islandora Google Groups for a solution.

* [Islandora Group](https://groups.google.com/forum/?hl=en&fromgroups#!forum/islandora)
* [Islandora Dev Group](https://groups.google.com/forum/?hl=en&fromgroups#!forum/islandora-dev)

## Development

If you would like to contribute, please get involved by attending our weekly [Tech Call](https://github.com/Islandora/islandora-community/wiki/Weekly-Open-Tech-Call). We love to hear from you!

If you would like to contribute code to the project, you need to be covered by an Islandora Foundation [Contributor License Agreement](https://github.com/Islandora/islandora-community/wiki/Onboarding-Checklist#contributor-license-agreements) or [Corporate Contributor License Agreement](https://github.com/Islandora/islandora-community/wiki/Onboarding-Checklist#contributor-license-agreements). Please see the [Contributor License Agreements](https://github.com/Islandora/islandora-community/wiki/Contributor-License-Agreements) page on the islandora-community wiki for more information.

We recommend using the [islandora-playbook](https://github.com/Islandora-Devops/islandora-playbook) to get started.

### General starter site development process

For development of this starter site proper, we anticipate something of a
particular flow being employed, to avoid having other features and modules creep
into the base configurations. The expected flow should go something like:

1. Provisioning an environment making use of the starter site
    * It _may_ be desirable to replace the environment's starter site installation with a repository clone of the
      starter site at this point to avoid otherwise manually copying changes out to a clone.
2. Importing the config of the starter site
    1. This should overwrite any configuration made by the provisioning process,
       including disabling any modules that should not be generally enabled, and
       installing those that _should_ be.
    2. This might be done with a command in the starter site directory such as:

        ```bash
        composer exec -- drush config:import sync
        ```

3. Perform the desired changes, such as:
    * Using `composer` to manage dependencies:
        * If updating any Drupal extensions, this should be followed by running
          Drupal's update process, in case there are update hooks to run which might
          update configuration.
    * Performing configuration on the site
4. Export the site's config, to capture any changed configuration:

    ```bash
    composer exec -- drush config:export sync
    ```

5. Copying the `config/sync` directory (with its contents) and `composer.json`
   and `composer.lock` files into a clone of the starter site git repository,
   committing them, pushing to a fork and making a pull request.
    * If the environment's starter site installation was replaced with a repository clone, you should be able to skip
      the copying, and just commit your changes, push to a fork and make a pull request to the upstream repository.

Periodically, it is expected that releases will be published/minted/tagged on the original repository; however, it is
important to note that automated updates across releases of this starter site is not planned to be supported. That
said, we plan to include changelogs with instructions of how the changes introduced since the last release might be
effected in derived site for those who wish to adopt altered/introduced functionality into their own site.

#### Development modules

A few modules are included in our `require-dev` section but left uninstalled from the Drupal site, as they may be of
general utility but especially development. Included are:
* [`config_inspector`](https://www.drupal.org/project/config_inspector/): Helps identify potential issues between
  the schemas defined and active configuration.
* [`devel`](https://www.drupal.org/project/devel): Blocks and tabs for miscellaneous tasks during development
* [`restui`](https://www.drupal.org/project/restui): Helper for configuration of the [core `rest` module](https://www.drupal.org/docs/8/core/modules/rest)

These modules might be
[enabled via the GUI or CLI](https://www.drupal.org/docs/extending-drupal/installing-modules#s-step-2-enable-the-module); however, they should be disabled before performing any kind of
config export, to avoid having their enabled state leak into configuration.

## License

[GPLv2](http://www.gnu.org/licenses/gpl-2.0.txt)
