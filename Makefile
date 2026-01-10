.PHONY: help pull init up down build setup traefik-http traefik-https-mkcert traefik-https-letsencrypt traefik-certs overwrite-starter-site create-starter-site-pr status clean ping

# If custom.makefile exists include it.
-include custom.Makefile

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

traefik-https-letsencrypt: ## Switch to HTTPS mode using Let's Encrypt ACME
	@./scripts/traefik-https-letsencrypt.sh

traefik-certs: ## Generate mkcert certificates
	@./scripts/generate-certs.sh

pull:
	@docker compose pull --ignore-buildable --ignore-pull-failures

build: pull ## Build the drupal container
	@./scripts/build.sh

init: ## Get the host machine configured to run ISLE
	@./scripts/init.sh

up: ## Start docker compose project with smart port allocation
	@./scripts/up.sh

up-%:  ## Start a specific service (e.g., make up-drupal)
	@docker compose up $* -d

down:  ## Stop/remove the docker compose project's containers and network.
	@docker compose down

down-%:  ## Stop/remove a specific service (e.g., make down-traefik)
	@docker compose down $*

logs-%:  ## Look at logs for a specific service (e.g., make logs-drupal)
	@docker compose logs $* --tail 20 -f

clean:  ## Delete all stateful data.
	@./scripts/clean.sh

ping:  ## Ensure site is available.
	@./scripts/ping.sh

overwrite-starter-site: ## Keep site template's drupal install in sync with islandora-starter-site
	@./scripts/overwrite-starter-site.sh

create-starter-site-pr: ## Create a PR for islandora-starter-site updates
	@./scripts/create-pr.sh
