#!/bin/bash
set -e

# Debug: Show environment and permissions
echo "--- ENVIRONMENT VARIABLES ---"
env

echo "--- /var/www/html PERMISSIONS ---"
ls -l /var/www/html
ls -l /var/www/html/wp-config.php || echo "wp-config.php missing"

# Always call the base image entrypoint to ensure WordPress setup logic runs
# (This will set up WordPress files and wp-config.php if needed)
docker-entrypoint.sh php-fpm &

# Wait for WordPress core files to be present before copying wp-config.php
WP_INDEX="/var/www/html/index.php"
MAX_WAIT=20
WAITED=0
while [ ! -f "$WP_INDEX" ] && [ $WAITED -lt $MAX_WAIT ]; do
    echo "Waiting for WordPress core files... ($WAITED/$MAX_WAIT)"
    sleep 1
    WAITED=$((WAITED+1))
done
if [ ! -f "$WP_INDEX" ]; then
    echo "ERROR: WordPress core files not found after $MAX_WAIT seconds."
    ls -l /var/www/html
    exit 1
fi

# Overwrite with our custom wp-config.php if it exists
if [ -f /wp-config-template.php ]; then
    cp /wp-config-template.php /var/www/html/wp-config.php
    chown www-data:www-data /var/www/html/wp-config.php
    chmod 644 /var/www/html/wp-config.php
    echo "Custom wp-config.php copied."
else
    echo "No custom wp-config-template.php found."
fi
ls -l /var/www/html/wp-config.php

# Debug: Test php-fpm config only (do not start php-fpm here, Supervisor will manage it)
php-fpm -tt || true

# List all PHP-FPM config files for debugging
ls -l /usr/local/etc/php-fpm.d/
ls -l /usr/local/etc/

# Show contents of all PHP-FPM config files for debugging
for f in /usr/local/etc/php-fpm.conf /usr/local/etc/php-fpm.d/*.conf; do
  echo "===== $f ====="
  cat "$f"
  echo
  echo "=============="
done

# Show PHP-FPM config info
php-fpm -i || true

# Start Supervisor (which starts nginx and php-fpm)
exec /usr/bin/supervisord -c /etc/supervisor/supervisor.conf
