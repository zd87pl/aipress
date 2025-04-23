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

# Create www-data group and user if they don't exist (they SHOULD in Debian)
# Also add to tty group just in case it helps with some logging scenarios
RUN groupadd --system --gid 33 www-data || echo "Group www-data already exists" && \
    useradd --system --uid 33 --gid www-data --shell /usr/sbin/nologin www-data || echo "User www-data already exists" && \
    usermod -a -G tty www-data

# Ensure /tmp is world-writable for logging
RUN chmod 1777 /tmp

# NOTE: WordPress core and PHP extensions are already included in the base image.
# NOTE: Base image entrypoint handles initial WP file setup & permissions.

# Remove all default pool configs to avoid conflicts
RUN rm -f /usr/local/etc/php-fpm.d/www.conf /usr/local/etc/php-fpm.d/www.conf.default /usr/local/etc/php-fpm.d/docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
# Copy PHP-FPM configuration files
COPY src/wordpress-runtime/php-fpm/00-logging.conf /usr/local/etc/php-fpm.d/00-logging.conf
COPY src/wordpress-runtime/php-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf

# Validate PHP-FPM configuration syntax
RUN php-fpm -t

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

# Copy custom wp-config template to root (not /var/www/html/)
COPY src/wordpress-runtime/wp-config-template.php /wp-config-template.php

# Copy test.php for PHP error/debug testing
COPY src/wordpress-runtime/test.php /var/www/html/test.php

# Copy the new entrypoint script
COPY src/wordpress-runtime/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Attempt to run FPM briefly in foreground during build to catch early fatal errors
# Install timeout utility first
RUN apt-get update && apt-get install -y --no-install-recommends coreutils && rm -rf /var/lib/apt/lists/*
RUN echo "Attempting brief FPM foreground run..." && \
    timeout 5s php-fpm -F || echo "FPM exited (expected or error)" && \
    echo "FPM foreground run attempt finished."

# Remove the docker-starter.sh logic
# COPY src/wordpress-runtime/docker-starter.sh /usr/local/bin/docker-starter.sh
# RUN chmod +x /usr/local/bin/docker-starter.sh

VOLUME /var/www/html/wp-content
EXPOSE 8080

# Healthcheck - Check for install or login page existence
# Note: Healthcheck might need adjustment if install.php is never expected after first setup
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-login.php || curl --fail http://127.0.0.1:8080/ || exit 1 # Check login page or root

# Start both nginx and php-fpm via Supervisor (required for Cloud Run)
ENTRYPOINT ["/docker-entrypoint.sh"]

# CMD is not needed when ENTRYPOINT is our custom entrypoint
