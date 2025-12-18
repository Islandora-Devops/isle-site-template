.PHONY: help init up down build setup traefik-http traefik-https-mkcert traefik-https-acme traefik-certs traefik-status

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

traefik-status: ## Show current HTTP/HTTPS configuration
	@echo "Current configuration:"
	@echo "  DOMAIN: $$(grep '^DOMAIN=' .env | cut -d= -f2 | tr -d '"')"
	@echo "  ENABLE_HTTPS: $$(grep '^ENABLE_HTTPS=' .env | cut -d= -f2 | tr -d '"')"
	@echo "  URI_SCHEME: $$(grep '^URI_SCHEME=' .env | cut -d= -f2 | tr -d '"')"
	@echo "  ENABLE_ACME: $$(grep '^ENABLE_ACME=' .env | cut -d= -f2 | tr -d '"')"

traefik-http: ## Switch to HTTP mode (default)
	@echo "Switching to HTTP mode..."
	@sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="false"/' .env && rm -f .env.bak
	@sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="http"/' .env && rm -f .env.bak
	@sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="false"/' .env && rm -f .env.bak
	@if grep -q '^DOMAIN=islandora.dev' .env; then \
		sed -i.bak 's/^DOMAIN=.*/DOMAIN=islandora.traefik.me/' .env && rm -f .env.bak; \
		echo "Domain changed from islandora.dev to islandora.traefik.me"; \
	fi
	@echo "Done! HTTP mode enabled."
	@docker compose down traefik
	@$(MAKE) up

traefik-https-mkcert: traefik-certs ## Switch to HTTPS mode using mkcert certificates
	@echo "Switching to HTTPS mode with mkcert..."
	@sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="true"/' .env && rm -f .env.bak
	@sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
	@sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="false"/' .env && rm -f .env.bak
	@sed -i.bak 's/^DOMAIN=.*/DOMAIN=islandora.dev/' .env && rm -f .env.bak
	@echo "Done! HTTPS mode enabled with mkcert certificates."
	@echo "Site will be available at: https://islandora.dev"
	@docker compose down traefik
	@$(MAKE) up

traefik-https-acme: ## Switch to HTTPS mode using Let's Encrypt ACME
	@echo "Switching to HTTPS mode with ACME (Let's Encrypt)..."
	@sed -i.bak 's/^ENABLE_HTTPS=.*/ENABLE_HTTPS="true"/' .env && rm -f .env.bak
	@sed -i.bak 's/^URI_SCHEME=.*/URI_SCHEME="https"/' .env && rm -f .env.bak
	@sed -i.bak 's/^ENABLE_ACME=.*/ENABLE_ACME="true"/' .env && rm -f .env.bak
	@echo "IMPORTANT: Make sure to configure ACME_EMAIL in .env before starting!"

traefik-certs: ## Generate mkcert certificates
	@echo "Generating certificates with mkcert..."
	@./scripts/generate-certs.sh
	@echo "Certificates generated successfully."

init:
	@docker compose up --abort-on-container-exit --exit-code-from init init 

build:
	@docker compose build drupal

up:
	@docker compose up --remove-orphans -d

down:
	@docker compose down

setup:
	@./scripts/setup.sh
