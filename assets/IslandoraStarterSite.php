<?php

namespace Islandora;

use Composer\Json\JsonFile;
use Composer\Script\Event;
use Composer\Util\Platform;

/**
 * Starter Site Composer helper.
 */
class StarterSite {

  /**
   * Root package installation event callback.
   *
   * Expected to be triggered on the `post-root-package-install` event, to track
   * the version of the project from which a project was derived.
   *
   * @see https://getcomposer.org/doc/articles/scripts.md#event-names
   */
  public static function rootPackageInstall(Event $event) {
    $composer = $event->getComposer();
    $package = $composer->getPackage();
    $version_file = new JsonFile('.starter_site_version');
    $version_file->write([
      'package' => "$package",
      'full-pretty-version' => $package->getFullPrettyVersion(),
      'pretty-string' => $package->getPrettyString(),
      'pretty-version' => $package->getPrettyVersion(),
      'unique-name' => $package->getUniqueName(),
      'version' => $package->getVersion(),
      'release-date' => $package->getReleaseDate(),
    ]);
  }

}
