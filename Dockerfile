ARG \
  DOCKER_REPOSITORY \
  TAG

FROM islandora/drupal:6.3.10

ARG TARGETARCH

COPY assets /var/www/drupal/assets
COPY recipes /var/www/drupal/recipes
COPY web /var/www/drupal/web
COPY composer.json composer.lock /var/www/drupal/

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install && \
    chown -R nginx:nginx . && \
    cleanup.sh

COPY config /var/www/drupal/config

COPY --link rootfs /

