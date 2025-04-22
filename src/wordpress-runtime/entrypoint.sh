#!/bin/bash
set -eo pipefail # Exit on error, treat unset variables as errors, propagate pipeline errors

# --- Configuration ---
# Variables like GCS_BUCKET_NAME will be used by supervisord config

# --- Validation (Optional: Check essential env vars if needed before exec) ---
# if [ -z "${GCS_BUCKET_NAME:-}" ]; then
#   echo "[Entrypoint] FATAL: GCS_BUCKET_NAME environment variable is not set." >&2
#   exit 1
# fi

# --- Execute CMD ---
# Run the command passed to the entrypoint via CMD in Dockerfile (supervisord)
echo "[Entrypoint] Executing command: $@"
exec "$@"
