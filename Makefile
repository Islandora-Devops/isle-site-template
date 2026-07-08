SHELL := /bin/bash

.PHONY: help create-starter-site-pr overwrite-starter-site sync-solr-conf
.SILENT:

# If custom.makefile exists include it.
-include custom.Makefile

help: ## Show this help message
	echo 'Usage: make [target]'
	echo ''
	echo 'Available targets:'
	awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%s\033[0m\t%s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort | column -t -s $$'\t'

overwrite-starter-site: ## Keep site template's drupal install in sync with islandora-starter-site
	./scripts/overwrite-starter-site.sh

sync-solr-conf: ## Refresh tracked Solr default core config from the running drupal container
	./scripts/sync-solr-conf.sh

create-starter-site-pr: ## Create a PR for islandora-starter-site updates
	./scripts/create-pr.sh
