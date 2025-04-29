# WordPress Runtime Experimental Optimizations Changelog

This document tracks the changes made to the experimental WordPress runtime container configuration compared to the original baseline configuration.

## 2025-04-27: Initial Optimizations (Session 1)

### Goal: Reduce cold start time and improve runtime performance.

### Changes:

1.  **Created `Dockerfile.experimental` based on `Dockerfile`:**
    *   Added `RUN` commands to set file ownership (`chown -R www-data:www-data /var/www/html`) and permissions (`find ... -exec chmod ...`) for `/var/www/html` during the image build phase.
    *   Changed the `COPY` command for the entrypoint script to point to `docker-entrypoint.experimental.sh`.
    *   Changed the `ENTRYPOINT` to use the copied script `/docker-entrypoint.sh` (which is the experimental one).
    *   Installed `coreutils` package (for `timeout` used in build check).

2.  **Created `docker-entrypoint.experimental.sh` based on `docker-entrypoint.sh`:**
    *   **Removed** the runtime `chown -R www-data:www-data /var/www/html` command.
    *   **Removed** the runtime `find /var/www/html -type d -exec chmod 755 {} \;` command.
    *   **Removed** the runtime `find /var/www/html -type f -exec chmod 644 {} \;` command.
    *   Kept the specific `chown www-data:www-data /var/www/html/wp-config.php` after copying the template.
    *   Added more descriptive logging messages (`[Entrypoint Experimental]`).

3.  **Created `php-fpm/www.experimental.conf`:**
    *   Based on `www.conf`.
    *   Changed `php_flag[display_errors]` from `on` to `off` for security.
    *   **Initial Tuning (Requires Testing):** Increased `pm.max_children` to `10` and adjusted `pm.start_servers`, `pm.min_spare_servers`, `pm.max_spare_servers` proportionally.

4.  **Created `nginx/nginx.experimental.conf`:**
    *   Based on `nginx.conf`.
    *   Increased `worker_connections` to `1024`.
    *   Enabled `multi_accept on`.
    *   Changed `error_log` level from `debug` to `warn`.
    *   Uncommented and configured detailed `gzip` settings.

5.  **Created `nginx/wordpress.experimental.conf`:**
    *   Based on `wordpress.conf`.
    *   Added `add_header Cache-Control "public";` to the static file location block.

6.  **Added PHP OPcache Configuration:**
    *   Created `php-fpm/zz-opcache.ini` with recommended starting values (memory, file caching, revalidation).

7.  **Updated `Dockerfile.experimental`:**
    *   Modified `COPY` commands to use `www.experimental.conf`, `nginx.experimental.conf`, and `wordpress.experimental.conf` instead of the originals.
    *   Added `COPY` command for `zz-opcache.ini`.
    *   **Fix (2025-04-27):** Added explicit `cp -a /usr/src/wordpress/. /var/www/html/` before setting permissions to ensure WP core files are present during build.
    *   **Fix (2025-04-27):** Removed redundant core file check from `docker-entrypoint.experimental.sh`.
8.  **Added Dynamic Tuning Capability (via Env Vars):**
    *   Modified `php-fpm/www.experimental.conf` to use placeholders (`${PHP_PM_MAX_CHILDREN}`, etc.) for `pm.*` settings.
    *   Modified `docker-entrypoint.experimental.sh` to:
        *   Set default values for `PHP_PM_*` environment variables.
        *   Use `envsubst` to substitute these environment variables into `/usr/local/etc/php-fpm.d/www.conf` before starting PHP-FPM.
        *   Run `php-fpm -t` validation *after* substitution.
    *   Modified `Dockerfile.experimental` to install `gettext-base` (needed for `envsubst`).

### Next Steps:

*   Build an image using `Dockerfile.experimental`.
*   Test the performance, focusing on:
    *   Cold start time reduction.
    *   Memory usage under load.
    *   Request throughput.
*   Iterate on `php-fpm/www.experimental.conf` `pm.*` settings based on testing results and Cloud Run instance memory allocation.
*   Consider further optimizations (e.g., multi-stage Docker build).

### Future Considerations / Ideas:

*   **Dynamic Runtime Tuning via Environment Variables:**
    *   **Concept:** Parameterize performance-critical settings (e.g., PHP-FPM `pm.max_children`, `pm.start_servers`) in configuration files (`www.experimental.conf`) to read values from environment variables (e.g., `$PHP_PM_MAX_CHILDREN`).
    *   **Mechanism:** The Control Plane could update these environment variables on a tenant's Cloud Run service based on monitoring analysis (potentially AI-driven) or user request. Cloud Run would then automatically deploy a new revision with the updated settings, allowing for dynamic adjustment of runtime performance profiles without rebuilding the image.
    *   **Benefits:** Allows fine-grained performance/cost balancing beyond just instance scaling, aligns with immutable infrastructure principles.
    *   **Requires:** Modifying config files to use env vars, enhancing Control Plane API, developing analysis/triggering logic.
*   **Multi-Stage Docker Builds:** Reduce final image size by installing build-time tools (like `coreutils`) in a separate build stage.
*   **Alternative Base Image:** Explore using Alpine-based images (`wordpress:fpm-alpine`) for potentially smaller sizes, requires careful testing.
