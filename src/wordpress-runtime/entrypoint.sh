#!/bin/bash
set -eo pipefail

echo "[Entrypoint] Starting script (No Supervisord)..."

# --- Configuration ---
GCS_BUCKET="${GCS_BUCKET_NAME:-}" 
WP_CONTENT_DIR="/var/www/html/wp-content"
WP_UID=$(id -u www-data)
WP_GID=$(id -g www-data)
# Using -o flags, including allow_other. Remove debug flags for cleaner logs.
GCSFUSE_OPTS="-o allow_other --implicit-dirs --uid ${WP_UID} --gid ${WP_GID} --file-mode 664 --dir-mode 775 --rename-dir-limit=1000" 

# --- Validation ---
if [ -z "$GCS_BUCKET" ]; then
  echo "[Entrypoint] WARNING: GCS_BUCKET_NAME environment variable is not set. Skipping GCS mount." >&2
  # Don't exit, proceed without gcsfuse
else
  if ! command -v gcsfuse &> /dev/null; then
      echo "[Entrypoint] FATAL: gcsfuse command not found." >&2
      exit 1
  fi
  # --- Mount GCS Bucket ---
  echo "[Entrypoint] Mounting GCS bucket in background: ${GCS_BUCKET} to ${WP_CONTENT_DIR}"
  # Run gcsfuse as root in the background. Log output to stdout.
  /usr/bin/gcsfuse ${GCSFUSE_OPTS} "${GCS_BUCKET}" "${WP_CONTENT_DIR}" --log-file /dev/stdout --log-format json &
  GCSFUSE_PID=$!
  echo "[Entrypoint] gcsfuse process started with PID $GCSFUSE_PID"
  # Give gcsfuse a moment to mount and check
  sleep 5 
  if ! mountpoint -q "$WP_CONTENT_DIR"; then
      echo "[Entrypoint] WARNING: Failed to mount GCS bucket after starting gcsfuse. Check logs." >&2
      # Don't exit, let WP run without wp-content mount potentially
      # kill $GCSFUSE_PID 2>/dev/null || true # Keep gcsfuse running even if mount fails initially?
  else
      echo "[Entrypoint] GCS mount verified."
  fi
fi

# --- Start Nginx ---
if ! command -v nginx &> /dev/null; then
    echo "[Entrypoint] FATAL: nginx command not found." >&2
    exit 1
fi
echo "[Entrypoint] Starting nginx in background..."
# Ensure pid directory exists and is writable (redundant with Dockerfile, but safe)
mkdir -p /var/run && chown www-data:www-data /var/run
# Start nginx as root, it will drop privileges for workers based on nginx.conf
/usr/sbin/nginx -g 'daemon off;' &
NGINX_PID=$!
echo "[Entrypoint] Nginx started with PID $NGINX_PID"
sleep 2 # Give nginx a moment to bind to the port

# --- Execute the Original CMD (should be php-fpm) ---
# Execute php-fpm in the foreground directly, replacing this script
# Use --allow-to-run-as-root because this script runs as root,
# but the pool config (www.conf) should ensure workers run as www-data.
# The -F flag is crucial to keep it in the foreground.
echo "[Entrypoint] Executing php-fpm..."
exec php-fpm -F --allow-to-run-as-root
