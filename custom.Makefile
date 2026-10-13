# Islandora Lite targets. Included automatically by the upstream Makefile (-include custom.Makefile).
# All targets are prefixed lite- so they never shadow an upstream target.

LITE_SITE_REPO ?= https://github.com/digitalutsc/islandora-lite-site.git
LITE_SITE_BRANCH ?= drupal-11
LITE_SITE_DIR := lite/drupal/rootfs/var/www/drupal
LITE_OWN_FILES := lite custom.Makefile docker-compose.lite.yml README.lite.md LOCALIZE.md QUICKSTART.md CLAUDE.md
LITE_EXEC := docker compose exec -T drupal with-contenv bash -lc

# Upstream scripts (ping.sh, up.sh, generate-certs.sh) need GNU `timeout`, which macOS
# lacks; without it `make up` reports "Site failed to come online" or follows the log
# forever. Provide lite/bin/timeout (perl alarm) for every target when the host has none.
ifeq ($(shell command -v timeout 2>/dev/null),)
export PATH := $(CURDIR)/lite/bin:$(PATH)
endif

.PHONY: lite-init lite-site lite-up lite-ping lite-cantaloupe lite-hydrate lite-drush lite-shell lite-login lite-status lite-upstream-check lite-upstream-pull

lite-init: ## Lite: create .env + override symlink, fetch the site, then upstream init (secrets, certs, build)
	if [ ! -f .env ]; then cp lite/env.sample .env; echo "Created .env from lite/env.sample"; fi
	if [ ! -e docker-compose.override.yml ]; then ln -s docker-compose.lite.yml docker-compose.override.yml; echo "Linked docker-compose.override.yml -> docker-compose.lite.yml"; fi
	$(MAKE) lite-site
	$(MAKE) init

lite-site: ## Lite: clone islandora-lite-site into the build context (if missing) and copy the complete composer.lock over it
	if [ ! -d "$(LITE_SITE_DIR)/.git" ]; then \
		echo "Cloning $(LITE_SITE_REPO) ($(LITE_SITE_BRANCH)) into $(LITE_SITE_DIR)"; \
		git clone --branch "$(LITE_SITE_BRANCH)" "$(LITE_SITE_REPO)" "$(LITE_SITE_DIR)"; \
	else \
		echo "Site already present at $(LITE_SITE_DIR) ($$(git -C $(LITE_SITE_DIR) rev-parse --short HEAD))"; \
	fi
	cp lite/site/composer.lock "$(LITE_SITE_DIR)/"
	echo "Applied lite/site overlay (composer.lock: the committed drupal-11 lock lacks the composer_site.json packages)"

lite-up: lite-init ## Lite: lite-init then upstream up (falls back to lite-ping where upstream ping.sh cannot run)
	$(MAKE) up || $(MAKE) lite-ping

lite-ping: ## Lite: readiness check without GNU timeout (macOS has none, so upstream ping.sh always fails there)
	URL="$$(grep '^URI_SCHEME=' .env | cut -d= -f2 | tr -d '\"')://$$(grep '^DOMAIN=' .env | cut -d= -f2 | tr -d '\"')"; \
	for i in 1 2 3 4 5 6 7 8 9 10; do \
		if curl -fs -m 10 "$$URL/" | grep -q Islandora; then echo "Site available at: $$URL"; exit 0; fi; \
		echo "Site is not live yet ($$i/10)"; sleep $$((5 * i)); \
	done; echo "Site failed to come online: $$URL" >&2; exit 1

lite-cantaloupe: ## Lite: translate lite/cantaloupe/conf (production's Cantaloupe config) for this image, test it, apply it
	if [ -f lite/cantaloupe/conf/cantaloupe.properties ]; then \
		lite/intake/cantaloupe-conf.sh lite/cantaloupe/conf lite/cantaloupe/stage; \
	else \
		echo "No lite/cantaloupe/conf/cantaloupe.properties: cantaloupe uses the image's config"; rm -rf lite/cantaloupe/stage; \
	fi
	docker compose up -d --no-deps cantaloupe

lite-hydrate: ## Lite: re-point Solr/Blazegraph/IIIF/ffmpeg config at this stack (re-runnable)
	$(LITE_EXEC) 'lite-hydrate.sh'

lite-drush: ## Lite: run drush in the drupal container, e.g. make lite-drush CMD="status"
	$(LITE_EXEC) 'drush $(CMD)'

lite-shell: ## Lite: interactive shell in the drupal container
	docker compose exec drupal with-contenv bash -l

lite-login: ## Lite: one-time login link
	$(LITE_EXEC) 'drush uli'

lite-status: ## Lite: upstream status plus the active service list
	$(MAKE) status
	echo ""
	echo "Active services: $$(docker compose config --services | sort | tr '\n' ' ')"
	echo "Disabled (profile): $$(docker compose --profile disabled config --services | sort | comm -13 <(docker compose config --services | sort) - | tr '\n' ' ')"

# Remote that carries the pristine isle-site-template: "upstream" when present (recommended:
# git remote add upstream https://github.com/Islandora-Devops/isle-site-template), else "origin".
LITE_UPSTREAM_REMOTE ?= $(shell git remote get-url upstream >/dev/null 2>&1 && echo upstream || echo origin)
LITE_UPSTREAM_BRANCH ?= main

lite-upstream-check: ## Lite: prove no upstream-tracked file is modified (prints nothing when clean)
	git fetch -q $(LITE_UPSTREAM_REMOTE) $(LITE_UPSTREAM_BRANCH) || echo "warn: could not fetch $(LITE_UPSTREAM_REMOTE); comparing against the last fetched $(LITE_UPSTREAM_REMOTE)/$(LITE_UPSTREAM_BRANCH)"
	git diff --stat $(LITE_UPSTREAM_REMOTE)/$(LITE_UPSTREAM_BRANCH) -- . $(foreach f,$(LITE_OWN_FILES),':(exclude)$(f)')
	git status --short -- . $(foreach f,$(LITE_OWN_FILES),':(exclude)$(f)') | grep -v '^??' || true

lite-upstream-pull: ## Lite: merge $(LITE_UPSTREAM_REMOTE)/main, then list mirrored upstream files that changed
	git fetch $(LITE_UPSTREAM_REMOTE) $(LITE_UPSTREAM_BRANCH)
	git merge --no-edit $(LITE_UPSTREAM_REMOTE)/$(LITE_UPSTREAM_BRANCH)
	echo ""
	echo "Upstream files mirrored by Lite that changed in this pull (port by hand, see README.lite.md):"
	git diff --stat ORIG_HEAD HEAD -- sample.env docker-compose.yml drupal/Dockerfile drupal/rootfs/etc || true

# ---------------------------------------------------------------------------------------
# Production-site replicas: lite/sites/<site>/ (local working folders). See LOCALIZE.md and
# lite/sites/README.md. All targets take SITE=<name>; the work is done by lite/bin/lite-site.
# ---------------------------------------------------------------------------------------
LITE_SITE := lite/bin/lite-site
.PHONY: site-add site-render site-check site-enable site-disable site-build site-up site-down site-intake site-deploy site-finalize site-placeholders site-users-from-lite site-solr-conf site-drush site-shell site-login site-db-shell site-dump site-reset sites

site-add: ## Site: scaffold lite/sites/$(SITE)/ (site.env, docker-compose.yml, README, NOTES.md) for a new site
	$(LITE_SITE) add $(SITE)

site-render: ## Site: re-render lite/sites/$(SITE)/docker-compose.yml from its site.env
	$(LITE_SITE) render $(SITE)

site-check: ## Site: validate the manual inputs (site.env, code, themes, database handover) before intake; read-only
	$(LITE_SITE) check $(SITE)

site-enable: ## Site: add the site to COMPOSE_FILE / COMPOSE_PROFILES in .env
	$(LITE_SITE) enable $(SITE)

site-disable: ## Site: stop the site and remove it from COMPOSE_FILE / COMPOSE_PROFILES
	$(LITE_SITE) disable $(SITE)

site-intake: ## Site: verify code + themes, stage them, normalize the database handover in db/, write NOTES.md
	$(LITE_SITE) intake $(SITE)

site-build: ## Site: build the drupal-$(SITE) image (FROM the Lite image + staged config/sync, themes, site-files)
	$(LITE_SITE) build $(SITE)

site-up: ## Site: start db-$(SITE) + drupal-$(SITE) and wait for the first-start localization
	$(LITE_SITE) up $(SITE)

site-deploy: ## Site: site-intake + site-build + site-up in one step (stops at the first failure)
	$(LITE_SITE) deploy $(SITE)

site-down: ## Site: stop and remove the two containers (volumes kept)
	$(LITE_SITE) down $(SITE)

site-finalize: ## Site: re-run the localization steps (re-point, Solr core, facets, updb, placeholders); FORCE=1 before first start
	$(LITE_SITE) finalize $(SITE)

site-placeholders: ## Site: (re)generate media placeholders; MODE=relink|per-file overrides site.env
	$(LITE_SITE) placeholders $(SITE)

site-users-from-lite: ## Site: replace the accounts of db-$(SITE) with the Lite site's (production accounts are never used)
	$(LITE_SITE) users-from-lite $(SITE)

site-solr-conf: ## Site: replace the shared Solr core's config with the vendored production one, RELOAD, mark for reindex
	$(LITE_SITE) solr-conf $(SITE)

site-drush: ## Site: drush in drupal-$(SITE), e.g. make site-drush SITE=memory CMD="status"
	$(LITE_SITE) drush $(SITE) $(CMD)

site-shell: ## Site: interactive shell in drupal-$(SITE)
	$(LITE_SITE) shell $(SITE)

site-login: ## Site: one-time login link for drupal-$(SITE)
	$(LITE_SITE) login $(SITE)

site-db-shell: ## Site: mysql shell in db-$(SITE)
	$(LITE_SITE) db-shell $(SITE)

site-dump: ## Site: mysqldump of db-$(SITE), normalized (no account rows), to DEST= (default lite/sites/$(SITE)/db/incoming/<site>-<date>.sql.xz)
	$(LITE_SITE) dump $(SITE) $(DEST)

site-reset: ## Site: DESTRUCTIVE for this site only: containers, volumes, image, stage/, normalized dump
	$(LITE_SITE) reset $(SITE)

sites: ## Site: list sites under lite/sites/ with enabled/running state
	$(LITE_SITE) list
