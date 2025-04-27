#!/bin/bash
set -exuo pipefail
trap 'echo "[Entrypoint] ERROR at line $LINENO"; exit 1' ERR

# Function to handle signals
function handle_signal {
    echo "[Entrypoint] Received signal, shutting down..."
    kill -TERM $NGINX_PID 2>/dev/null || true
    kill -TERM $PHP_FPM_PID 2>/dev/null || true
    exit 0
}

# Print environment variables relevant to WordPress/PHP
echo "[Entrypoint] Printing relevant environment variables..."
printenv | grep -E 'WORDPRESS|MYSQL|DB|PHP|NGINX' || true

# Set up signal handlers
trap handle_signal SIGTERM SIGINT

# --- Ensure WordPress core and config are present BEFORE starting services ---

# Check if WordPress core files are present (index.php is a good indicator)
if [ ! -f "/var/www/html/index.php" ] && [ -f "/var/www/html/wp-includes/version.php" ]; then
    echo >&2 "[Entrypoint] Warning: index.php missing but wp-includes/version.php exists. Assuming incomplete WP install. Re-copying core files."
    # If version.php exists but index.php doesn't, something is wrong, so re-copy
    find /var/www/html/ -mindepth 1 -maxdepth 1 -print -delete # Clear existing potentially partial files/dirs
    cp -a /usr/src/wordpress/. /var/www/html/
    echo "[Entrypoint] WordPress core files copied."
elif [ ! -f "/var/www/html/wp-includes/version.php" ]; then
    echo "[Entrypoint] WordPress core files not found (wp-includes/version.php missing), copying from /usr/src/wordpress..."
    # Use . to copy contents including hidden files if necessary, ensure target exists
    cp -a /usr/src/wordpress/. /var/www/html/
    echo "[Entrypoint] WordPress core files copied."
else
    echo "[Entrypoint] WordPress core files appear to be present."
fi

# Always copy our custom wp-config.php from /tmp where the Dockerfile placed it
if [ -f /tmp/wp-config-template.php ]; then
    echo "[Entrypoint] Forcing copy of custom wp-config.php from /tmp..."
    cp -f /tmp/wp-config-template.php /var/www/html/wp-config.php
    # Permissions will be set globally below, but set owner here
    chown www-data:www-data /var/www/html/wp-config.php
else
    echo >&2 "[Entrypoint] CRITICAL WARNING: /tmp/wp-config-template.php not found! Cannot apply custom config."
fi

# Fix permissions for WordPress files and directories
# This is critical for Cloud Run and PHP-FPM to work!
echo "[Entrypoint] Fixing permissions for /var/www/html..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Debug outputs
ls -lA /usr/local/etc/php-fpm.d/ || true
ls -lA /var/www/html || true
php-fpm -v || true
php-fpm -t || true

# --- Wait for Cloud SQL socket ---
SOCKET_PATH="$WORDPRESS_DB_HOST" # Get the path from env var
if [[ -n "$SOCKET_PATH" && "$SOCKET_PATH" == /cloudsql/* ]]; then
  echo "[Entrypoint] Waiting for Cloud SQL socket at $SOCKET_PATH..."
  WAIT_TIMEOUT=30 # seconds
  SECONDS_WAITED=0
  while ! [ -S "$SOCKET_PATH" ]; do
    if [ "$SECONDS_WAITED" -ge "$WAIT_TIMEOUT" ]; then
      echo >&2 "[Entrypoint] ERROR: Timed out waiting for Cloud SQL socket $SOCKET_PATH"
      ls -lA /cloudsql/ # List contents for debugging
      exit 1
    fi
    echo "[Entrypoint] Socket $SOCKET_PATH not found yet, waiting..."
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
  done
  echo "[Entrypoint] Cloud SQL socket $SOCKET_PATH found."
else
  echo "[Entrypoint] WORDPRESS_DB_HOST does not look like a Cloud SQL socket path ($SOCKET_PATH), skipping wait."
fi

# --- Start services ---
php-fpm -F &
PHP_FPM_PID=$!
echo "[Entrypoint] PHP-FPM started in background with PID $PHP_FPM_PID"
nginx -g 'daemon off;' &
NGINX_PID=$!
echo "[Entrypoint] nginx started in background with PID $NGINX_PID"

# Wait for either process to exit, then shutdown the other
wait -n $PHP_FPM_PID $NGINX_PID
EXIT_CODE=$?
echo "[Entrypoint] One of the services exited (code $EXIT_CODE), shutting down the other."
kill $PHP_FPM_PID $NGINX_PID 2>/dev/null || true
wait $PHP_FPM_PID $NGINX_PID || true
exit $EXIT_CODE
