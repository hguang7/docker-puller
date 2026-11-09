# syntax=docker/dockerfile:1
# Target: linux/amd64. Keep the PHP version fixed for repeatable releases.
FROM php:8.4.27-fpm-bookworm

# Pinned, public extension installer for the official PHP Docker image.
# It installs required Debian libraries and removes transient build dependencies.
COPY --from=mlocati/php-extension-installer:2.13.1 \
    /usr/bin/install-php-extensions /usr/local/bin/install-php-extensions

# Only install modules missing from the official base image; the installer
# skips modules that are already enabled. verify-php.sh enforces the full
# old Bitnami PHP 8.4.10 module baseline after the build.
RUN set -eux; \
    IPE_PROCESSOR_COUNT=2 install-php-extensions \
        bcmath bz2 calendar exif ftp gd gettext gmp intl ldap \
        mbstring mysqli pcntl pdo_mysql soap sockets tidy xsl zip; \
    install -d -m 0775 -o daemon -g daemon /var/www/html/logs; \
    php -v; \
    php-fpm -v

# Production PHP and FPM settings remain in the existing Kubernetes ConfigMap.
# Do not bake application code or PVC data into this image.
EXPOSE 9000
