<?php

use Drupal\search_api\Entity\Server;

$server_id = 'default_solr_server';
$server = Server::load($server_id);

if ($server) {
  try {
    $server->getBackend()->getSolrConnector()->pingServer();
    echo "Solr server connection test passed.\n";
  }
  catch (Exception $e) {
    echo "Solr server connection test failed: " . $e->getMessage() . "\n";
    exit(1);
  }
} else {
  echo "Solr server not found.\n";
  exit(1);
}
