# syntax=docker/dockerfile:1.5.1
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

COPY --link rootfs /

ENV PATH="/var/www/drupal/vendor/bin:$PATH"

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install -d /var/www/drupal && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
