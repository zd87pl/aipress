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

# Install gcsfuse - REMOVED

# NOTE: WordPress core and PHP extensions are already included in the base image.

# Copy custom PHP-FPM pool configuration (Sets log path)
COPY src/wordpress-runtime/php-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure Nginx 
COPY src/wordpress-runtime/nginx/nginx.conf /etc/nginx/nginx.conf
COPY src/wordpress-runtime/nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord
COPY src/wordpress-runtime/supervisor/supervisord.conf /etc/supervisor/supervisor.conf

# Configure fuse - REMOVED

# Setup directories and permissions
# Ensure /var/run exists for nginx pid and create log dir for php-fpm
# wp-content permissions handled by base image
RUN mkdir -p /var/run /var/log/php-fpm && \
    chown www-data:www-data /var/run /var/log/php-fpm

# Copy entrypoint script - REMOVED

VOLUME /var/www/html/wp-content # Standard WP volume, but content not mounted via fuse
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-admin/install.php || curl --fail http://127.0.0.1:8080/wp-login.php || exit 1 # Check for install or login page

# Use Supervisord as the entrypoint
ENTRYPOINT ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisor.conf"]

# CMD is not needed when ENTRYPOINT is supervisord
