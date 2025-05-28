# syntax=docker/dockerfile:1.5.1@sha256:d2d74ff22a0e47b21f4bbde337e2ac4cd0a02a2226ef79264878db3dc7e87df8
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

COPY --link rootfs /

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install -d /var/www/drupal && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
