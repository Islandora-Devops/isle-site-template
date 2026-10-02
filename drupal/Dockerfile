# syntax=docker/dockerfile:1.27.1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

COPY --link rootfs /

RUN --mount=type=cache,id=custom-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    composer install -d /var/www/drupal && \
    chown -R nginx:nginx /var/www/drupal && \
    cleanup.sh
