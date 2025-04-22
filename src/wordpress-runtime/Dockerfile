# Use the official WordPress FPM image (Debian based)
# Pin versions for consistency
ARG WORDPRESS_VERSION=6.5
ARG PHP_VERSION=8.2
FROM wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm

LABEL maintainer="AIPress PoC"
LABEL description="Stateless WordPress runtime with Nginx, PHP-FPM (No gcsfuse - Offload uploads)"

# Set DEBIAN_FRONTEND to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary additional packages: nginx, supervisor
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
    # Clean up apt lists
    && rm -rf /var/lib/apt/lists/*

# NOTE: WordPress core and PHP extensions are already included in the base image.
# NOTE: Base image entrypoint handles initial WP file setup & permissions.

# Copy custom PHP-FPM pool configuration (Sets log path)
COPY src/wordpress-runtime/php-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure Nginx 
COPY src/wordpress-runtime/nginx/nginx.conf /etc/nginx/nginx.conf
COPY src/wordpress-runtime/nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord
COPY src/wordpress-runtime/supervisor/supervisord.conf /etc/supervisor/supervisor.conf

# Remove explicit chown/chmod of /var/www/html - rely on base image entrypoint
# RUN echo "Setting ownership for /var/www/html..." && \
#     chown -R www-data:www-data /var/www/html && \
#     echo "Setting permissions for /var/www/html..." && \
#     find /var/www/html -type d -exec chmod 755 {} \; && \
#     find /var/www/html -type f -exec chmod 644 {} \; && \
#     echo "Verifying permissions:" && \
#     ls -ld /var/www/html && \
#     ls -lA /var/www/html/index.php

# Setup directories and permissions for runtime (logs, pids)
RUN mkdir -p /var/run /var/log/php-fpm && \
    chown www-data:www-data /var/run /var/log/php-fpm

# No custom entrypoint script needed when using Supervisord as ENTRYPOINT
VOLUME /var/www/html/wp-content 
EXPOSE 8080

# Healthcheck - Check for install or login page existence
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-admin/install.php || curl --fail http://127.0.0.1:8080/wp-login.php || exit 1

# Use Supervisord as the entrypoint
ENTRYPOINT ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisor.conf"]

# CMD is not needed when ENTRYPOINT is supervisord
