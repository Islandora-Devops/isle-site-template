.PHONY: help pull init up down build setup traefik-http traefik-https-mkcert traefik-https-acme traefik-certs overwrite-starter-site create-starter-site-pr status

PROJECT_NAME=$(shell grep '^COMPOSE_PROJECT_NAME=' .env | cut -d= -f2 | tr -d '"' || basename $(CURDIR))
DEFAULT_HTTP=80
DEFAULT_HTTPS=443

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

status: ## Show the current status of the development environment
	@./scripts/status.sh

traefik-http: ## Switch to HTTP mode (default)
	@./scripts/traefik-http.sh

traefik-https-mkcert: traefik-certs ## Switch to HTTPS mode using mkcert self-signed certificates
	@./scripts/traefik-https-mkcert.sh

traefik-https-acme: ## Switch to HTTPS mode using Let's Encrypt ACME
	@./scripts/traefik-https-acme.sh

traefik-certs: ## Generate mkcert certificates
	@./scripts/generate-certs.sh

pull:
	@docker compose pull --ignore-buildable --ignore-pull-failures

build: pull ## Build the drupal container
	@docker compose build

init: ## Get the host machine configured to run ISLE
	@./scripts/init.sh

up: ## Start docker compose project with smart port allocation
	@./scripts/up.sh

down:  ## Stop/remove the docker compose project's containers and network.
	@docker compose down

overwrite-starter-site: ## Keep site template's drupal install in sync with islandora-starter-site
	@./scripts/overwrite-starter-site.sh

create-starter-site-pr: ## Create a PR for islandora-starter-site updates
	@./scripts/create-pr.sh
