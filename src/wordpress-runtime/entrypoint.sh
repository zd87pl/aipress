#!/bin/bash
set -eo pipefail # Exit on error, treat unset variables as errors, propagate pipeline errors

# --- Configuration ---
GCS_BUCKET="${GCS_BUCKET_NAME:-}" # Provided by Cloud Run Env Var
WP_CONTENT_DIR="/var/www/html/wp-content"

# Get www-data UID/GID (should be 82 in alpine wordpress images)
WP_UID=$(id -u www-data)
WP_GID=$(id -g www-data)

# gcsfuse mount options
# implicit-dirs: Allows WP to create directories directly. Needed.
# allow-other: Allows the www-data user (PHP/Nginx) to access the mount. Requires fuse.conf change.
# uid/gid: Map ownership within the mount to www-data. Crucial.
# file-mode/dir-mode: Set permissions (adjust if needed, defaults might be okay with uid/gid)
# foreground: Keep gcsfuse running in the foreground if we weren't using supervisord
# key-file: Use Application Default Credentials (ADC) provided by Cloud Run SA, so not needed.
# stat-cache-ttl/type-cache-ttl: Caching options for performance tuning (start without, add later)
MOUNT_OPTS="allow_other,uid=${WP_UID},gid=${WP_GID},implicit_dirs,file_mode=664,dir_mode=775"
# Add performance tuning options later, e.g.: ,stat_cache_ttl=60s,type_cache_ttl=60s

# --- Validation ---
if [ -z "$GCS_BUCKET" ]; then
  echo "[Entrypoint] FATAL: GCS_BUCKET_NAME environment variable is not set." >&2
  exit 1
fi
if ! command -v gcsfuse &> /dev/null; then
    echo "[Entrypoint] FATAL: gcsfuse command not found." >&2
    exit 1
fi
if ! getent group fuse &>/dev/null; then
    echo "[Entrypoint] Warning: 'fuse' group does not exist. 'allow_other' might require it depending on fuse version/config." >&2
fi
# Check if SA has permissions? Difficult to do robustly here. Rely on mount failure.

# --- Dynamic WordPress Config (Minimal Example) ---
# Check if wp-config.php exists in the root, if not, copy default and modify
# WordPress base image handles basic setup using WORDPRESS_DB_* env vars if wp-config doesn't exist
# We might need more complex logic here later if salts etc. need to be injected from secrets

# --- Mount GCS Bucket ---
echo "[Entrypoint] Preparing to mount GCS bucket '$GCS_BUCKET' to '$WP_CONTENT_DIR'..."

# Check if already mounted (e.g., container restart without full pod recreation)
if ! mountpoint -q "$WP_CONTENT_DIR"; then
    echo "[Entrypoint] '$WP_CONTENT_DIR' is not a mountpoint. Attempting mount..."
    # Run gcsfuse as root. Requires the container to start as root initially.
    # The entrypoint script itself runs as the USER specified in Dockerfile (www-data),
    # UNLESS we run this script *before* switching user, or use sudo/su.
    # Easier: Run supervisord as root, let entrypoint run as root, start nginx/php-fpm as www-data.
    # *** Dockerfile needs USER removed or set to root if entrypoint needs root privileges ***
    # Let's assume for now the Dockerfile USER is root, and supervisord runs processes as www-data

    # Try mounting
    gcsfuse -o "${MOUNT_OPTS}" "${GCS_BUCKET}" "${WP_CONTENT_DIR}"
    # Check if mount succeeded
    if ! mountpoint -q "$WP_CONTENT_DIR"; then
        echo "[Entrypoint] FATAL: Failed to mount GCS bucket '$GCS_BUCKET' to '$WP_CONTENT_DIR'." >&2
        # Attempt to list bucket content for debugging permissions
        echo "[Entrypoint] Debug: Listing bucket root with 'gcsfuse --debug_fuse --debug_gcs -o ${MOUNT_OPTS} ${GCS_BUCKET} ${WP_CONTENT_DIR}' manually might help." >&2
        exit 1 # Or attempt fallback / logging
    fi
    echo "[Entrypoint] GCS bucket mounted successfully."

    # Post-mount permissions check/fix (gcsfuse mount options should handle this, but good safety check)
    # Need to ensure www-data can actually write. Find can be slow on large buckets.
    # echo "[Entrypoint] Verifying/Setting permissions on $WP_CONTENT_DIR..."
    # chown -R "${WP_UID}:${WP_GID}" "$WP_CONTENT_DIR" || echo "[Entrypoint] Warning: Could not chown $WP_CONTENT_DIR"
    # find "$WP_CONTENT_DIR" -not -user $WP_UID -exec chown $WP_UID {} \; || echo "[Entrypoint] Warning: Error during find/chown user"
    # find "$WP_CONTENT_DIR" -not -group $WP_GID -exec chgrp $WP_GID {} \; || echo "[Entrypoint] Warning: Error during find/chgrp group"
    # Instead of recursive chown, rely on mount options and check writeability
    if touch "${WP_CONTENT_DIR}/.healthcheck" && rm "${WP_CONTENT_DIR}/.healthcheck"; then
       echo "[Entrypoint] Write check to GCS mount successful."
    else
       echo "[Entrypoint] WARNING: Write check to GCS mount ${WP_CONTENT_DIR} failed. Check permissions and mount options." >&2
       # Consider exiting if write is mandatory?
    fi


else
    echo "[Entrypoint] Directory '$WP_CONTENT_DIR' is already a mountpoint."
fi


# --- Execute CMD ---
# Run the command passed to the entrypoint via CMD in Dockerfile
echo "[Entrypoint] Finished setup. Executing command: $@"
exec "$@"
```

**Important Correction:** For the entrypoint script to reliably run `gcsfuse` (which often requires root privileges for the initial mount, especially with `allow_other`), the Dockerfile should *not* switch `USER` to `www-data`. Instead, the entrypoint script runs as `root`, performs the mount, and then `supervisord` (also started as root) is configured to launch the `nginx` and `php-fpm` processes as the non-root `www-data` user.

I need to modify the Dockerfile slightly to remove the `USER www-data` line.

<replace_in_file>
<path>src/wordpress-runtime/Dockerfile</path>
<diff>
<<<<<<< SEARCH
RUN chmod +x /usr/local/bin/entrypoint.sh

# WordPress runs as www-data (UID 82 in alpine image)
USER www-data

# Set volume for external wp-content (managed via gcsfuse, but good practice)
=======
RUN chmod +x /usr/local/bin/entrypoint.sh

# NOTE: We run the entrypoint as root to handle gcsfuse mount.
# Supervisord will be configured to run php-fpm and nginx workers as www-data.
# USER www-data # REMOVED

# Set volume for external wp-content (managed via gcsfuse, but good practice)
>>>>>>> REPLACE
</diff>
</replace_in_file>[write_to_file for 'src/wordpress-runtime/entrypoint.sh'] Result: The content was successfully saved to src/wordpress-runtime/entrypoint.sh.

Here is the full, updated content of the file that was saved:

<final_file_content path="src/wordpress-runtime/entrypoint.sh">
#!/bin/bash
set -eo pipefail # Exit on error, treat unset variables as errors, propagate pipeline errors

# --- Configuration ---
GCS_BUCKET="${GCS_BUCKET_NAME:-}" # Provided by Cloud Run Env Var
WP_CONTENT_DIR="/var/www/html/wp-content"

# Get www-data UID/GID (should be 82 in alpine wordpress images)
WP_UID=$(id -u www-data)
WP_GID=$(id -g www-data)

# gcsfuse mount options
# implicit-dirs: Allows WP to create directories directly. Needed.
# allow-other: Allows the www-data user (PHP/Nginx) to access the mount. Requires fuse.conf change.
# uid/gid: Map ownership within the mount to www-data. Crucial.
# file-mode/dir-mode: Set permissions (adjust if needed, defaults might be okay with uid/gid)
# foreground: Keep gcsfuse running in the foreground if we weren't using supervisord
# key-file: Use Application Default Credentials (ADC) provided by Cloud Run SA, so not needed.
# stat-cache-ttl/type-cache-ttl: Caching options for performance tuning (start without, add later)
MOUNT_OPTS="allow_other,uid=${WP_UID},gid=${WP_GID},implicit_dirs,file_mode=664,dir_mode=775"
# Add performance tuning options later, e.g.: ,stat_cache_ttl=60s,type_cache_ttl=60s

# --- Validation ---
if [ -z "$GCS_BUCKET" ]; then
  echo "[Entrypoint] FATAL: GCS_BUCKET_NAME environment variable is not set." >&2
  exit 1
fi
if ! command -v gcsfuse &> /dev/null; then
    echo "[Entrypoint] FATAL: gcsfuse command not found." >&2
    exit 1
fi
if ! getent group fuse &>/dev/null; then
    echo "[Entrypoint] Warning: 'fuse' group does not exist. 'allow_other' might require it depending on fuse version/config." >&2
fi
# Check if SA has permissions? Difficult to do robustly here. Rely on mount failure.

# --- Dynamic WordPress Config (Minimal Example) ---
# Check if wp-config.php exists in the root, if not, copy default and modify
# WordPress base image handles basic setup using WORDPRESS_DB_* env vars if wp-config doesn't exist
# We might need more complex logic here later if salts etc. need to be injected from secrets

# --- Mount GCS Bucket ---
echo "[Entrypoint] Preparing to mount GCS bucket '$GCS_BUCKET' to '$WP_CONTENT_DIR'..."

# Check if already mounted (e.g., container restart without full pod recreation)
if ! mountpoint -q "$WP_CONTENT_DIR"; then
    echo "[Entrypoint] '$WP_CONTENT_DIR' is not a mountpoint. Attempting mount..."
    # Run gcsfuse as root. Requires the container to start as root initially.
    # The entrypoint script itself runs as the USER specified in Dockerfile (www-data),
    # UNLESS we run this script *before* switching user, or use sudo/su.
    # Easier: Run supervisord as root, let entrypoint run as root, start nginx/php-fpm as www-data.
    # *** Dockerfile needs USER removed or set to root if entrypoint needs root privileges ***
    # Let's assume for now the Dockerfile USER is root, and supervisord runs processes as www-data

    # Try mounting
    gcsfuse -o "${MOUNT_OPTS}" "${GCS_BUCKET}" "${WP_CONTENT_DIR}"
    # Check if mount succeeded
    if ! mountpoint -q "$WP_CONTENT_DIR"; then
        echo "[Entrypoint] FATAL: Failed to mount GCS bucket '$GCS_BUCKET' to '$WP_CONTENT_DIR'." >&2
        # Attempt to list bucket content for debugging permissions
        echo "[Entrypoint] Debug: Listing bucket root with 'gcsfuse --debug_fuse --debug_gcs -o ${MOUNT_OPTS} ${GCS_BUCKET} ${WP_CONTENT_DIR}' manually might help." >&2
        exit 1 # Or attempt fallback / logging
    fi
    echo "[Entrypoint] GCS bucket mounted successfully."

    # Post-mount permissions check/fix (gcsfuse mount options should handle this, but good safety check)
    # Need to ensure www-data can actually write. Find can be slow on large buckets.
    # echo "[Entrypoint] Verifying/Setting permissions on $WP_CONTENT_DIR..."
    # chown -R "${WP_UID}:${WP_GID}" "$WP_CONTENT_DIR" || echo "[Entrypoint] Warning: Could not chown $WP_CONTENT_DIR"
    # find "$WP_CONTENT_DIR" -not -user $WP_UID -exec chown $WP_UID {} \; || echo "[Entrypoint] Warning: Error during find/chown user"
    # find "$WP_CONTENT_DIR" -not -group $WP_GID -exec chgrp $WP_GID {} \; || echo "[Entrypoint] Warning: Error during find/chgrp group"
    # Instead of recursive chown, rely on mount options and check writeability
    if touch "${WP_CONTENT_DIR}/.healthcheck" && rm "${WP_CONTENT_DIR}/.healthcheck"; then
       echo "[Entrypoint] Write check to GCS mount successful."
    else
       echo "[Entrypoint] WARNING: Write check to GCS mount ${WP_CONTENT_DIR} failed. Check permissions and mount options." >&2
       # Consider exiting if write is mandatory?
    fi


else
    echo "[Entrypoint] Directory '$WP_CONTENT_DIR' is already a mountpoint."
fi


# --- Execute CMD ---
# Run the command passed to the entrypoint via CMD in Dockerfile
echo "[Entrypoint] Finished setup. Executing command: $@"
exec "$@"

</final_file_content>

IMPORTANT: For any future changes to this file, use the final_file_content shown above as your reference. This content reflects the current state of the file, including any auto-formatting (e.g., if you used single quotes but the formatter converted them to double quotes). Always base your SEARCH/REPLACE operations on this final version to ensure accuracy.

 <environment_details>
# VSCode Visible Files
src/wordpress-runtime/entrypoint.sh

# VSCode Open Tabs
ARCHITECTURE.md
BACKLOG.md
scripts/poc_gcp_setup.sh
infra/main.tf
infra/variables.tf
infra/modules/tenant_wordpress/main.tf
infra/modules/tenant_wordpress/variables.tf
infra/modules/tenant_wordpress/outputs.tf
src/control-plane/main.py
src/control-plane/requirements.txt
src/wordpress-runtime/Dockerfile
src/wordpress-runtime/entrypoint.sh
README.md

# Current Time
18/04/2025, 11:16:22 am (Europe/Warsaw, UTC+2:00)

# Context Window Usage
0 / 1,048.576K tokens used (0%)

# Current Mode
ACT MODE
</environment_details>[replace_in_file for 'src/wordpress-runtime/Dockerfile'] Result: The content was successfully saved to src/wordpress-runtime/Dockerfile.

Here is the full, updated content of the file that was saved:

<final_file_content path="src/wordpress-runtime/Dockerfile">
# Use the official WordPress FPM image (choose a specific version)
# Using Alpine variant for smaller size
ARG WORDPRESS_VERSION=6.5
ARG PHP_VERSION=8.2
FROM wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm-alpine

LABEL maintainer="AIPress PoC"
LABEL description="Stateless WordPress runtime with Nginx, PHP-FPM, and gcsfuse"

# Install necessary packages: nginx, supervisord, fuse3, ca-certificates, bash, curl (for healthcheck)
# fuse3 is required for gcsfuse v1.0.0+
# Adding tini as a lightweight init system
RUN apk add --no-cache \
        nginx \
        supervisor \
        fuse3 \
        ca-certificates \
        bash \
        curl \
        tini

# Install gcsfuse (using pre-built binary)
# Check https://github.com/GoogleCloudPlatform/gcsfuse/releases for latest URLs
ARG GCSFUSE_VERSION=2.0.1 # Use the latest recommended version
RUN set -eux; \
    apkArch="$(apk --print-arch)"; \
    case "$apkArch" in \
        x86_64) ARCH='amd64'; ;; \
        aarch64) ARCH='arm64'; ;; \
        *) echo >&2 "error: unsupported architecture: $apkArch"; exit 1 ;; \
    esac; \
    wget -O /usr/local/bin/gcsfuse "https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v${GCSFUSE_VERSION}/gcsfuse_${ARCH}"; \
    chmod +x /usr/local/bin/gcsfuse; \
    gcsfuse --version # Verify installation

# Install required/recommended PHP extensions for WordPress
# Base image includes common ones like mysqli, opcache, gd, zip
# Add any others commonly needed or specific to expected plugins
# Example: RUN docker-php-ext-install exif pcntl bcmath sockets
# Example: RUN pecl install redis && docker-php-ext-enable redis # If using Redis object cache later

# Configure Nginx
COPY ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY ./nginx/wordpress.conf /etc/nginx/conf.d/default.conf

# Configure Supervisord
COPY ./supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Configure fuse
# Allow non-root users to specify the allow_other mount option.
RUN echo "user_allow_other" >> /etc/fuse.conf

# Setup directories and permissions
# Ensure mount point exists before entrypoint. gcsfuse runs as root, WP processes as www-data.
# /run/nginx is needed for nginx pid
RUN mkdir -p /var/www/html/wp-content /run/nginx && \
    chown www-data:www-data /var/www/html/wp-content && \
    chown nginx:nginx /run/nginx

# Copy entrypoint script
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# NOTE: We run the entrypoint as root to handle gcsfuse mount.
# Supervisord will be configured to run php-fpm and nginx workers as www-data.
# USER www-data # REMOVED

# Set volume for external wp-content (managed via gcsfuse, but good practice)
# VOLUME /var/www/html/wp-content

# Healthcheck (Optional but recommended)
# Checks if Nginx is responding on the internal port
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail http://127.0.0.1:8080/wp-includes/images/blank.gif || exit 1

# Expose Nginx port (usually 8080 for Cloud Run)
EXPOSE 8080

# Use tini as the init system and run the entrypoint
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]

# Default command executed by entrypoint.sh
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

</final_file_content>

IMPORTANT: For any future changes to this file, use the final_file_content shown above as your reference. This content reflects the current state of the file, including any auto-formatting (e.g., if you used single quotes but the formatter converted them to double quotes). Always base your SEARCH/REPLACE operations on this final version to ensure accuracy.

 <environment_details>
# VSCode Visible Files
src/wordpress-runtime/Dockerfile

# VSCode Open Tabs
ARCHITECTURE.md
BACKLOG.md
scripts/poc_gcp_setup.sh
infra/main.tf
infra/variables.tf
infra/modules/tenant_wordpress/main.tf
infra/modules/tenant_wordpress/variables.tf
infra/modules/tenant_wordpress/outputs.tf
src/control-plane/main.py
src/control-plane/requirements.txt
src/wordpress-runtime/Dockerfile
src/wordpress-runtime/entrypoint.sh
README.md

# Current Time
18/04/2025, 11:16:28 am (Europe/Warsaw, UTC+2:00)

# Context Window Usage
0 / 1,048.576K tokens used (0%)

# Current Mode
ACT MODE
</environment_details>Okay, the `entrypoint.sh` script has been created, and the `Dockerfile` has been updated to remove the `USER www-data` directive, ensuring the entrypoint runs as root to perform the `gcsfuse` mount.

Now, let's add the configuration files needed by the Docker image.

First, the main Nginx configuration `src/wordpress-runtime/nginx/nginx.conf`:

<write_to_file>
<path>src/wordpress-runtime/nginx/nginx.conf</path>
<content>
# Basic Nginx configuration for Cloud Run WordPress

user nginx; # Run worker processes as nginx user (or www-data if preferred)
worker_processes auto;
pid /run/nginx/nginx.pid;
# include /etc/nginx/modules-enabled/*.conf; # Alpine doesn't use this structure by default

events {
    worker_connections 768;
    # multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off; # Hide nginx version

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging - Cloud Run captures stdout/stderr
    access_log /dev/stdout;
    error_log /dev/stderr warn; # Log warnings and errors

    gzip on;
    gzip_disable "msie6";
    # gzip_vary on;
    # gzip_proxied any;
    # gzip_comp_level 6;
    # gzip_buffers 16 8k;
    # gzip_http_version 1.1;
    # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Include virtual host configs
    include /etc/nginx/conf.d/*.conf;
}
