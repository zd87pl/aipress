#!/bin/bash
set -exuo pipefail

# Function to handle signals
function handle_signal {
    echo "[Entrypoint] Received signal, shutting down..."
    kill -TERM $NGINX_PID 2>/dev/null || true
    kill -TERM $PHP_FPM_PID 2>/dev/null || true
    exit 0
}

# Print environment variables relevant to WordPress/PHP
printenv | grep -E 'WORDPRESS|MYSQL|DB|PHP|NGINX' || true

# Set up signal handlers
trap handle_signal SIGTERM SIGINT

# Start nginx in background
echo "[Entrypoint] Starting nginx in background..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Check if nginx started successfully
sleep 1
if ! kill -0 $NGINX_PID 2>/dev/null; then
    echo "[Entrypoint] ERROR: nginx failed to start"
    exit 1
fi
echo "[Entrypoint] nginx started successfully with PID $NGINX_PID"

# Install WordPress core files if missing
if [ ! -f "/var/www/html/wp-includes/version.php" ]; then
    echo "[Entrypoint] WordPress files not found, copying from /usr/src/wordpress..."
    cp -a /usr/src/wordpress/* /var/www/html/
    echo "[Entrypoint] WordPress files copied."
else
    echo "[Entrypoint] WordPress files already present."
fi

# Copy our custom wp-config.php if it exists
if [ -f /wp-config-template.php ]; then
    echo "[Entrypoint] Copying custom wp-config.php..."
    cp /wp-config-template.php /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
    chmod 644 /var/www/html/wp-config.php
fi

# Fix permissions for WordPress files and directories
# This is critical for Cloud Run and PHP-FPM to work!
echo "[Entrypoint] Fixing permissions for /var/www/html..."
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# Print directory listing and permissions for debugging
echo "[Entrypoint] Directory listing for /var/www/html:"
ls -lA /var/www/html

# Start PHP-FPM in the foreground (main process)
echo "[Entrypoint] Starting PHP-FPM in foreground..."
exec php-fpm -F
