#!/bin/bash
set -exuo pipefail
trap 'echo "[Entrypoint Experimental] ERROR at line $LINENO"; exit 1' ERR

# Function to handle signals
function handle_signal {
    echo "[Entrypoint Experimental] Received signal, shutting down..."
    kill -TERM $NGINX_PID 2>/dev/null || true
    kill -TERM $PHP_FPM_PID 2>/dev/null || true
    exit 0
}

# Print environment variables relevant to WordPress/PHP
echo "[Entrypoint Experimental] Printing relevant environment variables..."
printenv | grep -E 'WORDPRESS|MYSQL|DB|PHP|NGINX' || true

# Set up signal handlers
trap handle_signal SIGTERM SIGINT

# --- Ensure WordPress config is present BEFORE starting services ---
# NOTE: WordPress core files are now copied during Docker build (Dockerfile.experimental)

# Always copy our custom wp-config.php from /tmp where the Dockerfile placed it
if [ -f /tmp/wp-config-template.php ]; then
    echo "[Entrypoint Experimental] Forcing copy of custom wp-config.php from /tmp..."
    cp -f /tmp/wp-config-template.php /var/www/html/wp-config.php
    # *** OPTIMIZATION: Only set permissions for the file we modified ***
    chown www-data:www-data /var/www/html/wp-config.php
    # Optional: Set minimal permissions if needed, but 644 from build should suffice
    # chmod 640 /var/www/html/wp-config.php # Example tighter permission
else
    echo >&2 "[Entrypoint Experimental] CRITICAL WARNING: /tmp/wp-config-template.php not found! Cannot apply custom config."
fi

# *** OPTIMIZATION: Removed slow chown -R and find commands. Permissions are set during build. ***
# echo "[Entrypoint Experimental] Fixing permissions for /var/www/html..."
# chown -R www-data:www-data /var/www/html
# find /var/www/html -type d -exec chmod 755 {} \;
# find /var/www/html -type f -exec chmod 644 {} \;
echo "[Entrypoint Experimental] Skipping runtime permission fix for /var/www/html (done during build)."

# Debug outputs
ls -lA /usr/local/etc/php-fpm.d/ || true
ls -lA /var/www/html || true # Verify wp-config.php owner/perms
php-fpm -v || true
# php-fpm -t || true # Config test is done after substitution now

# --- Substitute Env Vars into PHP-FPM Config ---
# Define defaults if variables are not set
: "${PHP_PM_MAX_CHILDREN:=10}" # Default based on initial experimental setting
: "${PHP_PM_START_SERVERS:=3}"
: "${PHP_PM_MIN_SPARE_SERVERS:=2}"
: "${PHP_PM_MAX_SPARE_SERVERS:=5}"
# : "${PHP_PM_MAX_REQUESTS:=500}" # Example if using max_requests

# Export the variables so envsubst can see them
export PHP_PM_MAX_CHILDREN PHP_PM_START_SERVERS PHP_PM_MIN_SPARE_SERVERS PHP_PM_MAX_SPARE_SERVERS # PHP_PM_MAX_REQUESTS

FPM_CONF_FILE="/usr/local/etc/php-fpm.d/www.conf" # The file with placeholders copied by Dockerfile

echo "[Entrypoint Experimental] Substituting PHP-FPM pool config in $FPM_CONF_FILE..."
# Use envsubst to replace placeholders from the template and write to a temporary file, then overwrite original
# Important: Only substitute specific variables to avoid unintended replacements
# Note: Requires 'gettext' package providing envsubst to be installed in the Docker image.
envsubst '${PHP_PM_MAX_CHILDREN} ${PHP_PM_START_SERVERS} ${PHP_PM_MIN_SPARE_SERVERS} ${PHP_PM_MAX_SPARE_SERVERS}' < "$FPM_CONF_FILE" > "$FPM_CONF_FILE.tmp" && \
    mv "$FPM_CONF_FILE.tmp" "$FPM_CONF_FILE" && \
    echo "[Entrypoint Experimental] Substituted values written to $FPM_CONF_FILE." && \
    echo "[Entrypoint Experimental] Verifying final config:" && \
    cat "$FPM_CONF_FILE" && \
    php-fpm -t || \
    { echo >&2 "[Entrypoint Experimental] ERROR: Substitution or final FPM config validation failed!"; exit 1; }


# --- Wait for Cloud SQL socket ---
SOCKET_PATH="$WORDPRESS_DB_HOST" # Get the path from env var
if [[ -n "$SOCKET_PATH" && "$SOCKET_PATH" == /cloudsql/* ]]; then
  echo "[Entrypoint Experimental] Waiting for Cloud SQL socket at $SOCKET_PATH..."
  WAIT_TIMEOUT=30 # seconds
  SECONDS_WAITED=0
  while ! [ -S "$SOCKET_PATH" ]; do
    if [ "$SECONDS_WAITED" -ge "$WAIT_TIMEOUT" ]; then
      echo >&2 "[Entrypoint Experimental] ERROR: Timed out waiting for Cloud SQL socket $SOCKET_PATH"
      ls -lA /cloudsql/ # List contents for debugging
      exit 1
    fi
    echo "[Entrypoint Experimental] Socket $SOCKET_PATH not found yet, waiting..."
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
  done
  echo "[Entrypoint Experimental] Cloud SQL socket $SOCKET_PATH found."
else
  echo "[Entrypoint Experimental] WORDPRESS_DB_HOST does not look like a Cloud SQL socket path ($SOCKET_PATH), skipping wait."
fi

# --- Start services ---
echo "[Entrypoint Experimental] Starting PHP-FPM..."
php-fpm -F &
PHP_FPM_PID=$!
echo "[Entrypoint Experimental] PHP-FPM started in background with PID $PHP_FPM_PID"

echo "[Entrypoint Experimental] Starting Nginx..."
nginx -g 'daemon off;' &
NGINX_PID=$!
echo "[Entrypoint Experimental] nginx started in background with PID $NGINX_PID"

# Wait for either process to exit, then shutdown the other
wait -n $PHP_FPM_PID $NGINX_PID
EXIT_CODE=$?
echo "[Entrypoint Experimental] One of the services exited (code $EXIT_CODE), shutting down the other."
kill $PHP_FPM_PID $NGINX_PID 2>/dev/null || true
wait $PHP_FPM_PID $NGINX_PID || true
exit $EXIT_CODE
