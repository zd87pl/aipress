# Use the official WordPress FPM image (Debian based)
# Pin versions for consistency
ARG WORDPRESS_VERSION=6.5
ARG PHP_VERSION=8.2
FROM wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm

LABEL maintainer="AIPress PoC"
LABEL description="Stateless WordPress runtime with Nginx, PHP-FPM, and gcsfuse (Official WP Debian based)"

# Set DEBIAN_FRONTEND to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary additional packages: nginx, fuse3, and gcsfuse dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        fuse3 \
        lsb-release \
        curl \
        gnupg \
    # Clean up apt lists
    && rm -rf /var/lib/apt/lists/*

# Install gcsfuse using Google's recommended APT method for Debian/Ubuntu
# See: https://cloud.google.com/storage/docs/gcsfuse/install#linux-install
RUN set -eux; \
    export GCSFUSE_REPO=gcsfuse-`lsb_release -cs`; \
    # Add Google's APT repository
    echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" > /etc/apt/sources.list.d/gcsfuse.list; \
    # Import Google Cloud public key
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg; \
    chmod a+r /usr/share/keyrings/google-cloud.gpg; \
    # Update package list and install gcsfuse
    apt-get update; \
    apt-get install -y --no-install-recommends gcsfuse; \
    # Verify installation
    gcsfuse --version; \
    # Clean up apt lists
    rm -rf /var/lib/apt/lists/*

# NOTE: WordPress core and PHP extensions (gd, mysqli, zip, opcache) are already included in the base image.

# Copy custom PHP-FPM pool configuration
COPY src/wordpress-runtime/php-fpm/www.conf /usr/local/etc/php-fpm.d/www.conf

# Configure Nginx (Base image might have its own, but we override)
# Paths are relative to the build context (project root)
COPY src/wordpress-runtime/nginx/nginx.conf /etc/nginx/nginx.conf
COPY src/wordpress-runtime/nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord - REMOVED

# Configure fuse
# Allow non-root users to specify the allow_other mount option.
RUN echo "user_allow_other" >> /etc/fuse.conf || true # Allow failure if file doesn't exist initially

# Setup directories and permissions
# Base image sets up /var/www/html, ensure wp-content exists and is writable by www-data
# Ensure /var/run exists for nginx pid and create log dir for php-fpm
RUN mkdir -p /var/www/html/wp-content /var/run /var/log/php-fpm && \
    chown -R www-data:www-data /var/www/html/wp-content && \
    chown www-data:www-data /var/run /var/log/php-fpm

# Copy entrypoint script
COPY src/wordpress-runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# NOTE: Base image entrypoint is overridden below. We run our entrypoint as root.
VOLUME /var/www/html/wp-content
EXPOSE 8080

# Healthcheck (Optional but recommended)
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-includes/images/blank.gif || exit 1

# Use our custom entrypoint script
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# CMD is inherited from the base image (php-fpm)
