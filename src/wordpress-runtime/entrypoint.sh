#!/bin/bash
set -eo pipefail

echo "[Entrypoint] Starting script..."

# --- Configuration ---
GCS_BUCKET="${GCS_BUCKET_NAME:-}" 
WP_CONTENT_DIR="/var/www/html/wp-content"
WP_UID=$(id -u www-data)
WP_GID=$(id -g www-data)
# Use -o flags again, including allow_other, as running as root bypasses some permission issues
# Remove debug flags for now unless needed
GCSFUSE_OPTS="-o allow_other --implicit-dirs --uid ${WP_UID} --gid ${WP_GID} --file-mode 664 --dir-mode 775 --rename-dir-limit=1000" 

# --- Validation ---
if [ -z "$GCS_BUCKET" ]; then
  echo "[Entrypoint] FATAL: GCS_BUCKET_NAME environment variable is not set." >&2
  exit 1
fi
if ! command -v gcsfuse &> /dev/null; then
    echo "[Entrypoint] FATAL: gcsfuse command not found." >&2
    exit 1
fi
if ! command -v nginx &> /dev/null; then
    echo "[Entrypoint] FATAL: nginx command not found." >&2
    exit 1
fi

# --- Mount GCS Bucket in Background ---
echo "[Entrypoint] Mounting GCS bucket in background: ${GCS_BUCKET} to ${WP_CONTENT_DIR}"
# Run gcsfuse as root in the background
/usr/bin/gcsfuse ${GCSFUSE_OPTS} "${GCS_BUCKET}" "${WP_CONTENT_DIR}" &
GCSFUSE_PID=$!
echo "[Entrypoint] gcsfuse process started with PID $GCSFUSE_PID"
# Give gcsfuse a moment to mount and check
sleep 5 
if ! mountpoint -q "$WP_CONTENT_DIR"; then
    echo "[Entrypoint] FATAL: Failed to mount GCS bucket after starting gcsfuse." >&2
    # Check gcsfuse logs if needed (might go to syslog or stdout/stderr if not daemonized)
    # tail /var/log/syslog 
    kill $GCSFUSE_PID 2>/dev/null || true
    exit 1
fi
echo "[Entrypoint] GCS mount verified."

# --- Start Nginx in Background ---
echo "[Entrypoint] Starting nginx in background..."
# Ensure pid directory exists and is writable (redundant with Dockerfile, but safe)
mkdir -p /var/run && chown www-data:www-data /var/run
# Start nginx as root, it will drop privileges for workers based on nginx.conf
/usr/sbin/nginx -g 'daemon off;' &
NGINX_PID=$!
echo "[Entrypoint] Nginx started with PID $NGINX_PID"
sleep 2 # Give nginx a moment to bind to the port

# --- Execute the Original CMD (should be php-fpm) ---
# The base wordpress:fpm image's CMD should handle running php-fpm correctly.
# It often includes logic to handle initial setup if needed.
echo "[Entrypoint] Executing CMD: $@"
exec "$@"
