# Drupal <!-- omit in toc -->

This image is where the customizations and configuration for your institutions
site will live.

- [Dependencies](#dependencies)
- [Updating](#updating)
  - [Installation](#installation)
  - [Composer](#composer)
  - [Solr Configuration](#solr-configuration)

## Dependencies

Requires `islandora/drupal` docker image to build. Please refer to the [drupal]
image for additional information.

## Updating

### Installation

### Composer

### Solr Configuration

If updating the [solr] image be sure to update the configuration in
[./rootfs/opt/solr/server/solr/default/conf]


[drupal]: https://github.com/Islandora-Devops/isle-buildkit/tree/main/drupal#readme
[solr]: https://github.com/Islandora-Devops/isle-buildkit/tree/main/solr#readme
[./rootfs/opt/solr/server/solr/default/conf]: ./rootfs/opt/solr/server/solr/default/conf
