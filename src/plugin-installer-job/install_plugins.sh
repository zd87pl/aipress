#!/bin/bash
set -euo pipefail
# Expect arguments: DB_HOST DB_NAME DB_USER DB_PASSWORD PLUGIN_NAME ACTIVATE_FLAG SITE_URL
DB_HOST="${1}"
DB_NAME="${2}"
DB_USER="${3}"
DB_PASSWORD="${4}"
PLUGIN_NAME="${5}"
ACTIVATE_FLAG="${6}" # "true" or "false"
SITE_URL="${7:-http://localhost}" # Optional SITE_URL, default to localhost if not provided

WP_CLI_PATH="/usr/local/bin/wp"
WP_PATH="/tmp/dummy-wp-path-$$" # Temporary dummy path for WP-CLI DB operations

echo "[Installer Script] Received request for plugin: ${PLUGIN_NAME}, Activate: ${ACTIVATE_FLAG}"
echo "[Installer Script] Using DB Host: ${DB_HOST}, DB Name: ${DB_NAME}, DB User: ${DB_USER}"
echo "[Installer Script] Site URL (for context): ${SITE_URL}"

# Construct common WP-CLI arguments for database connection
COMMON_ARGS=(
    "--path=${WP_PATH}"
    "--url=${SITE_URL}"
    "--dbhost=${DB_HOST}"
    "--dbname=${DB_NAME}"
    "--dbuser=${DB_USER}"
    "--dbpass=${DB_PASSWORD}"
    "--skip-plugins" # Skip loading installed plugins for performance/stability
    "--skip-themes"  # Skip loading themes
    "--quiet"        # Reduce output unless error
    "--allow-root"   # Necessary in container environments
)

# Check if WordPress core is installed (basic check: can connect to DB and query options?)
# We might need a more robust check, but this is a start.
echo "[Installer Script] Checking DB connection and WP install status..."
if ! "${WP_CLI_PATH}" db check "${COMMON_ARGS[@]}"; then
    echo "[Installer Script] ERROR: Cannot connect to database or WordPress not fully installed. Aborting plugin install."
    exit 1
fi
echo "[Installer Script] DB connection successful."

# Install the plugin
echo "[Installer Script] Attempting to install plugin: ${PLUGIN_NAME}..."
if ! "${WP_CLI_PATH}" plugin install "${PLUGIN_NAME}" "${COMMON_ARGS[@]}"; then
    # Check if installation failed because it's already installed
    if "${WP_CLI_PATH}" plugin is-installed "${PLUGIN_NAME}" "${COMMON_ARGS[@]}"; then
        echo "[Installer Script] Plugin '${PLUGIN_NAME}' is already installed."
    else
        echo "[Installer Script] ERROR: Failed to install plugin '${PLUGIN_NAME}'."
        # Consider attempting an update instead? wp plugin update ...
        exit 1 # Exit on failure for now
    fi
fi

# Activate the plugin if requested
if [[ "${ACTIVATE_FLAG}" == "true" ]]; then
    echo "[Installer Script] Attempting to activate plugin: ${PLUGIN_NAME}..."
    if ! "${WP_CLI_PATH}" plugin activate "${PLUGIN_NAME}" "${COMMON_ARGS[@]}"; then
        # Check if activation failed because it's already active
        if "${WP_CLI_PATH}" plugin is-active "${PLUGIN_NAME}" "${COMMON_ARGS[@]}"; then
             echo "[Installer Script] Plugin '${PLUGIN_NAME}' is already active."
        else
            echo "[Installer Script] WARNING: Failed to activate plugin '${PLUGIN_NAME}' after installation."
            # Don't exit, just warn, as installation might have succeeded.
        fi
    else
        echo "[Installer Script] Plugin '${PLUGIN_NAME}' activated successfully."
    fi
else
    echo "[Installer Script] Activation not requested for plugin: ${PLUGIN_NAME}."
fi

echo "[Installer Script] Finished processing plugin: ${PLUGIN_NAME}."
exit 0
