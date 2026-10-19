# Default build arguments (modify .env instead when "docker compose build")
ARG PKP_TOOL=ojs                           # Options are: ojs, omp, ops.
ARG PKP_VERSION=3_4_0-9                    # Same as PKP's versions.
ARG WEB_SERVER=alpine:3.24                 # Alpine runtime base image; CI may override this with Harbor.
ARG WEB_USER=www-data                      # Web user for Apache/PHP.
ARG WEB_PATH=/var/www/html/ojs              # OJS application directory.
ARG BUILD_PKP_APP_OS=alpine:3.24           # OS used to download/build the app; CI may override this with Harbor.
ARG BUILD_PKP_APP_PATH=/app                # Where the app is built.
ARG BUILD_LABEL=notset
ARG PKP_UPDATE_DEPENDENCIES=1              # Refresh Composer/JS dependencies.


# Stage 1: Download PKP source code from released tarball.
# hadolint ignore=DL3006,DL3026
FROM ${BUILD_PKP_APP_OS} AS pkp_code

ARG PKP_TOOL \
    PKP_VERSION \
    BUILD_PKP_APP_PATH \
    PKP_UPDATE_DEPENDENCIES

# Harbor's mirrored base image may define a non-root default user; package and
# dependency installation must run as root during the build.
# hadolint ignore=DL3002,DL3066
USER root

# The base image is configurable and defaults to a versioned Alpine image.
WORKDIR ${BUILD_PKP_APP_PATH}

# Alpine package versions are intentionally resolved from the selected Alpine release.
# hadolint ignore=DL3018
RUN apk add --no-cache curl gzip tar && \
    pkpVersion=$(awk -v version="${PKP_VERSION}" 'BEGIN { gsub(/_/, ".", version); print version }') && \
    curl -sSL -O "https://pkp.sfu.ca/${PKP_TOOL}/download/${PKP_TOOL}-${pkpVersion}.tar.gz" && \
    tar --strip-components=1 -xzf "${PKP_TOOL}-${pkpVersion}.tar.gz" && \
    rm "${PKP_TOOL}-${pkpVersion}.tar.gz"

# The PKP release tarball contains a vendor tree that can lag behind current
# security fixes. Refresh the dependencies against the PHP runtime used by
# this image. The version changes below stay within the OJS 3.4 dependency
# model, except for TinyMCE and firebase/php-jwt where the vulnerable major
# versions have no fixed release in their old major line.
# Use WORKDIR and Composer's working-dir option so each command remains POSIX sh-compatible.
WORKDIR ${BUILD_PKP_APP_PATH}/lib/pkp

# Alpine package versions are intentionally resolved from the selected Alpine release.
# hadolint ignore=DL3018
RUN if [ "${PKP_UPDATE_DEPENDENCIES}" = "1" ]; then \
        apk add --no-cache composer php85-dom php85-ftp php85-session php85-tokenizer php85-xml php85-xmlwriter && \
        composer config audit.block-insecure false && \
        composer config platform.php 8.5 && \
        sed -i \
            -e 's#"adodb/adodb-php": "v5.20.18"#"adodb/adodb-php": "^5.22.10"#' \
            -e 's#"firebase/php-jwt": "[^"]*"#"firebase/php-jwt": "^6.0"#' \
            -e 's#"jquery/validation": "1.19.5"#"jquery/validation": "1.20.0"#' \
            -e 's#"smarty/smarty": "v4.3.1"#"smarty/smarty": "^4.5.3"#' \
            -e 's#"tinymce/tinymce": "[^"]*"#"tinymce/tinymce": "^7.9.3"#' \
            -e 's#"version": "1.19.5"#"version": "1.20.0"#' \
            -e 's#jquery-validation-1.19.5.tgz#jquery-validation-1.20.0.tgz#' \
            composer.json && \
        composer update --no-dev --no-interaction --no-progress --no-scripts --with-all-dependencies --ignore-platform-req=ext-* && \
        composer --working-dir="${BUILD_PKP_APP_PATH}/plugins/paymethod/paypal" config audit.block-insecure false && \
        composer --working-dir="${BUILD_PKP_APP_PATH}/plugins/paymethod/paypal" config platform.php 8.5 && \
        composer --working-dir="${BUILD_PKP_APP_PATH}/plugins/paymethod/paypal" update --no-dev --no-interaction --no-progress --no-scripts --with-all-dependencies --ignore-platform-req=ext-*; \
    fi


# Stage 2: Alpine runtime with Apache and PHP 8.5.
# hadolint ignore=DL3006,DL3026
FROM ${WEB_SERVER}

ARG PKP_TOOL \
    PKP_VERSION \
    WEB_SERVER \
    WEB_USER \
    WEB_PATH \
    BUILD_PKP_APP_PATH \
    BUILD_LABEL

# Harbor's mirrored base image may define a non-root default user; install the
# runtime packages as root before switching to www-data below.
# hadolint ignore=DL3066
USER root

LABEL maintainer="Public Knowledge Project <marc.bria@uab.es>"
LABEL org.opencontainers.image.vendor="Public Knowledge Project"
LABEL org.opencontainers.image.title="PKP ${PKP_TOOL} Web Application"
LABEL org.opencontainers.image.version="${PKP_VERSION}"
LABEL org.opencontainers.image.revision="${PKP_TOOL}-${PKP_VERSION}#${BUILD_LABEL}"
LABEL org.opencontainers.image.description="Runs a ${PKP_TOOL} application over ${WEB_SERVER} with Apache and PHP 8.5."
LABEL io.containers.rootless="true"

# Alpine's PHP packages use /etc/php85 rather than the official PHP image's
# /usr/local/etc/php layout.
ENV SERVERNAME="localhost" \
    WWW_PATH_CONF="/etc/apache2/httpd.conf" \
    WWW_PATH_ROOT="/var/www" \
    WEB_PATH="${WEB_PATH}" \
    HTTPS="on" \
    PKP_CLI_INSTALL="0" \
    PKP_CONFIG_SYNC="0" \
    PKP_INSTALLED="Off" \
    PKP_DB_HOST="${PKP_DB_HOST:-db}" \
    PKP_DB_NAME="${PKP_DB_NAME:-pkp}" \
    PKP_DB_USER="${PKP_DB_USER:-pkp}" \
    PKP_DB_PASSWORD="${PKP_DB_PASSWORD:-changeMePlease}" \
    PKP_WEB_CONF="/etc/apache2/conf.d/pkp.conf" \
    PKP_CONF="${WEB_PATH}/config.inc.php" \
    PHP_INI_DIR="/etc/php85/conf.d" \
    PKP_CMD="/usr/local/bin/pkp-start"

# php85-apache2 keeps the existing Apache architecture while the remaining
# php85-* packages replace the extensions built by docker-php-ext-install.
# Upgrade packages inherited from the Alpine base image before installing the
# runtime. This keeps security fixes such as zlib updates from being masked by
# an older package already present in the base image.
# Alpine package versions are intentionally resolved from the selected Alpine release.
# hadolint ignore=DL3018
RUN apk upgrade --no-cache && \
    apk add --no-cache \
        apache2 \
        apache2-ssl \
        antiword \
        ca-certificates \
        curl \
        ghostscript \
        openssl \
        poppler-utils \
        tar \
        unzip \
        xz \
        php85-apache2 \
        php85-bcmath \
        php85-curl \
        php85-dom \
        php85-fileinfo \
        php85-ftp \
        php85-gd \
        php85-gettext \
        php85-iconv \
        php85-intl \
        php85-mbstring \
        php85-mysqli \
        php85-openssl \
        php85-pdo \
        php85-pdo_mysql \
        php85-pdo_pgsql \
        php85-pgsql \
        php85-phar \
        php85-session \
        php85-simplexml \
        php85-sodium \
        php85-tokenizer \
        php85-xml \
        php85-xmlreader \
        php85-xmlwriter \
        php85-xsl \
        php85-zip

# Alpine's Apache package uses the apache user by default. The container is
# deliberately run as www-data, so make Apache use the same unprivileged user.
RUN if ! grep -q '^www-data:' /etc/group; then addgroup -S -g 82 www-data; fi && \
    if ! grep -q '^www-data:' /etc/passwd; then adduser -S -D -H -u 82 -G www-data www-data; fi && \
    sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' "${WWW_PATH_CONF}" && \
    sed -i -e "s/^User .*/User ${WEB_USER}/" \
           -e "s/^Group .*/Group ${WEB_USER}/" \
           "${WWW_PATH_CONF}" && \
    printf '\nServerName localhost\n' >> "${WWW_PATH_CONF}" && \
    mkdir -p /etc/ssl/apache2 /var/files "${WEB_PATH}" /run/apache2 "${PHP_INI_DIR}" /var/www/logs && \
    ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log && \
    ln -sf /dev/stdout /var/www/logs/access.log && \
    ln -sf /dev/stderr /var/www/logs/error.log && \
    chown -R "${WEB_USER}:${WEB_USER}" /var/log/apache2 /var/www/logs

# Copy source code and configuration files.
WORKDIR ${WEB_PATH}
COPY --from=pkp_code "${BUILD_PKP_APP_PATH}" .
COPY "templates/pkp/root/" /
COPY "volumes/config/apache.pkp.conf" "${PKP_WEB_CONF}"

# Final configuration steps.
# /etc/os-release is provided by the Alpine base image at build time.
# hadolint ignore=SC1091
RUN cp -a config.TEMPLATE.inc.php "${PKP_CONF}" && \
    sed -i -e 's#^files_dir = files$#files_dir = /var/files#' "${PKP_CONF}" && \
    chown -R "${WEB_USER}:${WEB_USER}" "${WWW_PATH_ROOT}" && \
    chown "${WEB_USER}:${WEB_USER}" "${PKP_WEB_CONF}" && \
    chown -R "${WEB_USER}:${WEB_USER}" /etc/ssl/apache2 /run/apache2 && \
    chmod +x "${PKP_CMD}" && \
    . /etc/os-release && \
    echo "${PKP_TOOL}-${PKP_VERSION} with ${WEB_SERVER} over ${ID}-${VERSION_ID} [build: $(date +%Y%m%d-%H%M%S)]" \
        > "${WEB_PATH}/container.version" && \
    cat "${WEB_PATH}/container.version"

# Expose web ports and declare volumes.
EXPOSE 8080
EXPOSE 8443

VOLUME [ "/var/files", "${WEB_PATH}/public" ]

# Run the web process as an unprivileged user.
USER ${WEB_USER}

CMD ["/usr/local/bin/pkp-start"]
