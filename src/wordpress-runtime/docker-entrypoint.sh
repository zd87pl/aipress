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

# Install WordPress core files if missing
if [ ! -f "/var/www/html/wp-includes/version.php" ]; then
    echo "[Entrypoint] WordPress files not found, copying from /usr/src/wordpress..."
    cp -a /usr/src/wordpress/* /var/www/html/
    echo "[Entrypoint] WordPress files copied."
else
    echo "[Entrypoint] WordPress files already present."
fi

# Always copy our custom wp-config.php
if [ -f /wp-config-template.php ]; then
    echo "[Entrypoint] Forcing copy of custom wp-config.php..."
    cp -f /wp-config-template.php /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
    chmod 644 /var/www/html/wp-config.php
else
    echo "[Entrypoint] WARNING: /wp-config-template.php not found!"
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
