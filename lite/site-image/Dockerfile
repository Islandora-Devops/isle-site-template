# syntax=docker/dockerfile:1
# Production-site replica image for isle-site-lite.
#
# Built per site by lite/sites/<site>/docker-compose.yml with three build contexts:
#   lite      = service:drupal                  the Lite image (composer set already installed)
#   stage     = lite/sites/<site>/stage         config/sync, web/themes/custom/*, web/modules/custom (from `make site-intake`)
#   sitefiles = lite/sites/<site>/site-files    small public files named in config (theme logo, ...)
# Nothing is composer-installed here: composer.json/composer_site.json/lock always come
# from islandora-lite-site through the Lite image; the site contributes configuration.
FROM lite

# DejaVu font for the ImageMagick text in generated placeholder images.
RUN apk add --no-cache ttf-dejavu

# The site's exported configuration replaces the Lite one.
RUN rm -rf /var/www/drupal/config/sync
COPY --from=stage --chown=nginx:nginx / /var/www/drupal/

# The site's production Solr config (lite/sites/<site>/solr/conf, adapted by intake) is not
# part of the Drupal tree: lite-solr-conf.sh reads it from /opt/lite/solr/conf.
RUN if [ -d /var/www/drupal/solr/conf ]; then \
      mkdir -p /opt/lite/solr && mv /var/www/drupal/solr/conf /opt/lite/solr/conf && rm -rf /var/www/drupal/solr; \
    fi

# Themes handed over outside composer may still declare Drupal 8/9/10 only.
RUN set -e; for f in /var/www/drupal/web/themes/*/*.info.yml /var/www/drupal/web/themes/custom/*/*.info.yml; do \
      [ -e "$f" ] || continue; \
      sed -i -e '/^core: 8\.x$/d' -e 's/^core_version_requirement:.*/core_version_requirement: ^10 || ^11/' "$f"; \
      grep -q '^core_version_requirement: \^10 || \^11$' "$f" || echo "core_version_requirement: ^10 || ^11" >> "$f"; \
      echo "theme $(basename "$(dirname "$f")"): $(grep '^core_version_requirement' "$f")"; \
    done

COPY --from=sitefiles / /opt/lite/site-files/

# Localize first-start (replaces the Lite install.sh), finalize script, media placeholder
# scripts, the Solr core installer (lite-solr-conf.sh), and the MariaDB-client --skip-ssl wrapper (the db is MySQL 8 with a self-signed cert).
COPY rootfs/ /
RUN chmod +x /etc/s6-overlay/scripts/install.sh /usr/local/bin/lite-site-finalize.sh /usr/local/bin/lite-accounts-from-lite.sh /usr/local/bin/lite-solr-conf.sh /usr/local/bin/mariadb-skip-ssl-wrapper && \
    for c in mariadb mariadb-dump mariadb-admin mariadb-check mysql mysqldump mysqladmin mysqlcheck; do ln -sf mariadb-skip-ssl-wrapper /usr/local/bin/$c; done && \
    rm -f /installed
