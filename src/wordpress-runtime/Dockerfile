# Use the official WordPress FPM image (Debian based)
# Pin versions for consistency
ARG WORDPRESS_VERSION=6.5
ARG PHP_VERSION=8.2
FROM wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm

LABEL maintainer="AIPress PoC"
LABEL description="Stateless WordPress runtime with Nginx, PHP-FPM (TESTING - No gcsfuse)"

# Set DEBIAN_FRONTEND to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary additional packages: nginx, supervisor
# Removing fuse3, lsb-release, curl, gnupg for this test
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
    # Clean up apt lists
    && rm -rf /var/lib/apt/lists/*

# Install gcsfuse - COMMENTED OUT FOR TESTING
# RUN set -eux; \
#     export GCSFUSE_REPO=gcsfuse-`lsb_release -cs`; \
#     # Add Google's APT repository
#     echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" > /etc/apt/sources.list.d/gcsfuse.list; \
#     # Import Google Cloud public key
#     curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg; \
#     chmod a+r /usr/share/keyrings/google-cloud.gpg; \
#     # Update package list and install gcsfuse
#     apt-get update; \
#     apt-get install -y --no-install-recommends gcsfuse; \
#     # Verify installation
#     gcsfuse --version; \
#     # Clean up apt lists
#     rm -rf /var/lib/apt/lists/*

# NOTE: WordPress core and PHP extensions are already included in the base image.

# Copy custom PHP-FPM pool configuration (Sets log path)
COPY src/wordpress-runtime/php-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure Nginx 
COPY src/wordpress-runtime/nginx/nginx.conf /etc/nginx/nginx.conf
COPY src/wordpress-runtime/nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord
COPY src/wordpress-runtime/supervisor/supervisord.conf /etc/supervisor/supervisor.conf

# Configure fuse - COMMENTED OUT FOR TESTING
# RUN echo "user_allow_other" >> /etc/fuse.conf || true 

# Add a simple index.php for testing Nginx/PHP-FPM
RUN echo "<?php phpinfo(); ?>" > /var/www/html/index.php \
    && chown www-data:www-data /var/www/html/index.php

# Setup directories and permissions
# Ensure necessary directories exist and have correct ownership
# /var/run for nginx pid, /var/log/php-fpm for logs, /run/php for socket
# No need to chown wp-content as it's not mounted/used in this test
RUN mkdir -p /var/run /var/log/php-fpm /run/php && \
    chown www-data:www-data /var/run /var/log/php-fpm /run/php

# Copy entrypoint script (Might be empty, but still needed by ENTRYPOINT)
COPY src/wordpress-runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# VOLUME /var/www/html/wp-content # Not needed for this test
EXPOSE 8080

# Healthcheck - Should work if phpinfo page is served
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/index.php || exit 1

# Use Supervisord as the entrypoint (to start nginx, php-fpm)

# CMD is not needed when ENTRYPOINT is supervisord
