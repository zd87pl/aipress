# Use the official PHP-FPM image based on Debian Bookworm
ARG PHP_VERSION=8.2
FROM php:${PHP_VERSION}-fpm-bookworm

LABEL maintainer="AIPress PoC"
LABEL description="Stateless WordPress runtime with Nginx, PHP-FPM, and gcsfuse (Debian based)"

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary packages: nginx, supervisord, fuse3, ca-certificates, curl, gnupg, wget, unzip
RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        fuse3 \
        ca-certificates \
        curl \
        gnupg \
        wget \
        unzip \
    # Clean up apt lists
    && rm -rf /var/lib/apt/lists/*

# Install common PHP extensions required by WordPress
# ref: https://github.com/docker-library/wordpress/blob/master/latest/php8.2/fpm/Dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        libzip-dev \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j "$(nproc)" \
        gd \
        mysqli \
        opcache \
        zip \
    # Other common extensions (optional, add if needed by plugins)
    # exif \
    # pcntl \
    # bcmath \
    # sockets \
    && rm -rf /var/lib/apt/lists/*

# Install gcsfuse using Google's recommended APT method for Debian/Ubuntu
# See: https://cloud.google.com/storage/docs/gcsfuse/install#linux-install
RUN set -eux; \
    # Install dependencies needed for adding repo/key
    apt-get update && apt-get install -y --no-install-recommends \
        lsb-release \
        curl \
        gnupg \
    && rm -rf /var/lib/apt/lists/*; \
    # Use explicit codename (bookworm) as lsb_release might not be reliable in all contexts
    # export GCSFUSE_REPO=gcsfuse-`lsb_release -cs`; \
    export GCSFUSE_REPO=gcsfuse-bookworm; \
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

# Download and extract WordPress
ARG WORDPRESS_VERSION=latest # Or specify a version like 6.5
RUN set -eux; \
    cd /var/www/html; \
    # Download WordPress (use wget as curl might be different in base image)
    wget "https://wordpress.org/${WORDPRESS_VERSION}.zip"; \
    # Extract WordPress
    unzip "${WORDPRESS_VERSION}.zip"; \
    # Remove zip file
    rm "${WORDPRESS_VERSION}.zip"; \
    # Move contents from wordpress subdir to /var/www/html
    mv wordpress/* .; \
    rmdir wordpress; \
    # Set correct ownership (www-data user/group should exist in php:fpm image)
    chown -R www-data:www-data /var/www/html

# Configure Nginx
# Paths are relative to the build context (project root)
COPY src/wordpress-runtime/nginx/nginx.conf /etc/nginx/nginx.conf
COPY src/wordpress-runtime/nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord
COPY src/wordpress-runtime/supervisor/supervisord.conf /etc/supervisor/supervisor.conf
# Note: Debian supervisord might look for config in /etc/supervisor/supervisor.conf by default

# Configure fuse
# Allow non-root users to specify the allow_other mount option.
RUN echo "user_allow_other" >> /etc/fuse.conf || true # Allow failure if file doesn't exist initially

# Setup directories and permissions
# /var/www/html/wp-content should be created by WP extraction
# Ensure /var/run exists for nginx pid and is owned by www-data
RUN mkdir -p /var/run && \
    chown www-data:www-data /var/www/html/wp-content && \
    chown www-data:www-data /var/run # Nginx worker runs as www-data in this setup

# Copy entrypoint script
# Path is relative to the build context (project root)
COPY src/wordpress-runtime/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# NOTE: We run the entrypoint as root to handle gcsfuse mount.
# Supervisord will be configured to run php-fpm and nginx workers as www-data.
# USER www-data # Keep removed

# Define WordPress volume (though managed by gcsfuse)
VOLUME /var/www/html/wp-content

# Healthcheck (Optional but recommended)
# Checks if Nginx is responding on the internal port
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-includes/images/blank.gif || exit 1

# Expose Nginx port (usually 8080 for Cloud Run)
EXPOSE 8080

# Use supervisord to manage processes (no need for tini with supervisord as PID 1)
# Specify the correct config file path for supervisord
ENTRYPOINT ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisor.conf"] # Add -n to run in foreground

# Default CMD is not needed when ENTRYPOINT is supervisord
# CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
