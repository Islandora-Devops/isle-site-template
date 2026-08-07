<?php

/**
 * @file
 * One-off migration: move managed files from fedora:// to private://.
 *
 * Used when removing the Fedora (fcrepo) integration from a site that already
 * has content. Copies each file's bytes out of Fedora into the private file
 * system, then rewrites file_managed.uri. A URI is only rewritten after the
 * copy's byte count matches the size recorded in the database, so a partial or
 * failed transfer leaves the original reference untouched. Re-running is safe:
 * an existing destination of the correct size is reused.
 *
 * Prerequisites, all of which must hold BEFORE Fedora is torn down:
 * - The fcrepo service is running.
 * - DRUPAL_DEFAULT_FCREPO_URL is set for the drupal service, so
 *   settings.php registers the fedora flysystem driver.
 * - conf/traefik/fcrepo.yml exists, because the flysystem root is
 *   http://fcrepo.${DOMAIN}/fcrepo/rest/ and therefore resolves through
 *   Traefik. Without that router every read fails.
 * - drush cache:rebuild has been run since the wrapper was registered,
 *   as the stream wrapper registry is cached.
 *
 * Usage:
 *   docker compose cp scripts/migrate-fedora-to-private.php drupal:/tmp/
 *   docker compose exec drupal drush php:script /tmp/migrate-fedora-to-private.php
 *
 * Afterwards, point the media field storage configs at the new scheme and
 * clear caches plus image derivatives:
 *   drush config:set field.storage.media.FIELD settings.uri_scheme private
 *   drush cache:rebuild && drush image:flush --all
 *
 * Take a database dump first: drush sql:dump --gzip.
 */

use Drupal\Core\File\FileSystemInterface;

$db = \Drupal::database();
$fs = \Drupal::service('file_system');

$rows = $db->query('SELECT fid, uri, filesize FROM file_managed WHERE uri LIKE :p ORDER BY fid', [':p' => 'fedora://%'])->fetchAll();
$total = count($rows);
printf("to migrate: %d\n", $total);

$ok = 0;
$reused = 0;
$fail = 0;
$bytes = 0;

foreach ($rows as $r) {
  $src = $r->uri;
  $dest = 'private://' . substr($src, strlen('fedora://'));
  $dir = dirname($dest);

  if (!$fs->prepareDirectory($dir, FileSystemInterface::CREATE_DIRECTORY)) {
    printf("FAIL mkdir fid=%d %s\n", $r->fid, $dir);
    $fail++;
    continue;
  }

  // Reuse a complete copy from an earlier run.
  clearstatcache(TRUE, $dest);
  if (file_exists($dest) && (int) @filesize($dest) === (int) $r->filesize) {
    $db->update('file_managed')->fields(['uri' => $dest])->condition('fid', $r->fid)->execute();
    $reused++;
    continue;
  }

  if (!@copy($src, $dest)) {
    printf("FAIL copy fid=%d %s\n", $r->fid, $src);
    $fail++;
    continue;
  }

  // Only rewrite the URI once the copy is verified byte-for-byte by size.
  clearstatcache(TRUE, $dest);
  $dsize = (int) @filesize($dest);
  if ($dsize !== (int) $r->filesize) {
    printf("FAIL size fid=%d expected=%d got=%d\n", $r->fid, $r->filesize, $dsize);
    $fail++;
    continue;
  }

  $db->update('file_managed')->fields(['uri' => $dest])->condition('fid', $r->fid)->execute();
  $ok++;
  $bytes += $dsize;

  if (($ok + $reused) % 50 === 0) {
    printf("... %d/%d\n", $ok + $reused, $total);
  }
}

printf("RESULT migrated=%d reused=%d failed=%d bytes=%d\n", $ok, $reused, $fail, $bytes);
