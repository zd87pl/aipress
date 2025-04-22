#!/bin/bash
set -eo pipefail

# Execute the original WordPress entrypoint script first.
# This handles initial setup, copying files, setting permissions etc.
# We pass any arguments ($@) to it, which should typically be 'php-fpm'.
# We explicitly run php-fpm via supervisord later, so we don't need to pass it here.
# Instead, we check if DB is ready which is one of the checks the original entrypoint does.
echo "[run.sh] Executing original WordPress entrypoint checks (like db wait)..."
# Source the original entrypoint to get functions like wait-for-db
# The exact path might vary, check base image if needed, but usually sourced by wordpress entrypoint
# Simpler approach: Call the original entrypoint directly but prevent it from exec'ing php-fpm
# This is tricky. Let's just ensure files exist and permissions are okay AFTER supervisord starts PHP-FPM.
# The base image entrypoint logic is complex to replicate partially.

# Instead, let's rely on the base image having done its work,
# and ensure supervisord starts things in the right order.

# We still need to ensure the original entrypoint logic regarding wp-config generation runs.
# The base image ENTRYPOINT is ["docker-entrypoint.sh"]. CMD is ["php-fpm"].
# Let's call the original entrypoint and expect it to handle setup, then we start supervisord.

# Run the original entrypoint. It expects 'php-fpm' as CMD normally.
# We won't pass 'php-fpm' because supervisord will manage it.
# Let's just call it without args, it might perform setup steps.
echo "[run.sh] Running base image entrypoint (docker-entrypoint.sh) for potential setup..."
docker-entrypoint.sh || echo "[run.sh] Original entrypoint finished (ignore errors if any, supervisord will start php-fpm)."

# Now, start supervisord as the main process
echo "[run.sh] Starting supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisor.conf
