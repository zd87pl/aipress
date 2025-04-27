<?php
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
/**
 * The base configuration for WordPress
 *
 * This file uses environment variables to configure WordPress, suitable for containerized environments.
 */

// Function to get environment variables with a default value
function get_env_var($key, $default = null) {
    $value = getenv($key);
    if ($value === false) {
        // Fallback for Apache/mod_php where getenv might not work as expected
        // Also useful if variables are injected differently
        $value = $_ENV[$key] ?? $_SERVER[$key] ?? false; 
    }
    return ($value !== false) ? $value : $default;
}

// ** Database settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', get_env_var('WORDPRESS_DB_NAME', 'wordpress') );
define( 'DB_USER', get_env_var('WORDPRESS_DB_USER', 'root') );
define( 'DB_PASSWORD', get_env_var('WORDPRESS_DB_PASSWORD', '') );

// Determine DB Host and Socket based on environment variable
$_db_host_env = get_env_var('WORDPRESS_DB_HOST');
$_db_socket_path = null;
if (strpos($_db_host_env, '/cloudsql/') === 0) {
    // It's a Cloud SQL socket path
    define( 'DB_HOST', 'localhost' ); // Use localhost when socket is specified
    $_db_socket_path = $_db_host_env;
    ini_set('mysqli.default_socket', $_db_socket_path);
    error_log("[WP Config] Detected Cloud SQL socket. DB_HOST set to 'localhost', mysqli.default_socket set to: " . $_db_socket_path);
} else {
    // Assume it's a regular hostname/IP
    define( 'DB_HOST', $_db_host_env );
    error_log("[WP Config] Using standard DB_HOST: " . DB_HOST);
}

// --- BEGIN DB SOCKET DEBUG ---
error_log("WP DB DEBUG: DB_HOST constant = " . DB_HOST);
if ($_db_socket_path) {
    error_log("WP DB DEBUG: mysqli.default_socket = " . ini_get('mysqli.default_socket'));
    error_log("WP DB DEBUG: Socket file '{$_db_socket_path}' exists? " . (file_exists($_db_socket_path) ? 'yes' : 'no'));
}
// --- END DB SOCKET DEBUG ---

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', get_env_var('WORDPRESS_DB_CHARSET', 'utf8mb4') );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', get_env_var('WORDPRESS_DB_COLLATE', '') );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define('AUTH_KEY',         get_env_var('WORDPRESS_AUTH_KEY',         'put your unique phrase here'));
define('SECURE_AUTH_KEY',  get_env_var('WORDPRESS_SECURE_AUTH_KEY',  'put your unique phrase here'));
define('LOGGED_IN_KEY',    get_env_var('WORDPRESS_LOGGED_IN_KEY',    'put your unique phrase here'));
define('NONCE_KEY',        get_env_var('WORDPRESS_NONCE_KEY',        'put your unique phrase here'));
define('AUTH_SALT',        get_env_var('WORDPRESS_AUTH_SALT',        'put your unique phrase here'));
define('SECURE_AUTH_SALT', get_env_var('WORDPRESS_SECURE_AUTH_SALT', 'put your unique phrase here'));
define('LOGGED_IN_SALT',   get_env_var('WORDPRESS_LOGGED_IN_SALT',   'put your unique phrase here'));
define('NONCE_SALT',       get_env_var('WORDPRESS_NONCE_SALT',       'put your unique phrase here'));
/**#@-*/

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = get_env_var('WORDPRESS_TABLE_PREFIX', 'wp_');

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define( 'WP_DEBUG', filter_var(get_env_var('WORDPRESS_DEBUG', 'false'), FILTER_VALIDATE_BOOLEAN) );

/* Add any custom values between this line and the "stop editing" line. */

// If we're behind a Cloud Run proxy, trust the X-Forwarded-* headers.
// IMPORTANT: Only do this if you KNOW your proxy sets these headers correctly!
// Cloud Run does set X-Forwarded-Proto and X-Forwarded-For.
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && strtolower($_SERVER['HTTP_X_FORWARDED_PROTO']) === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
if (isset($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    // Use the first IP in the list (client IP)
    $forwarded_for_ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
    $_SERVER['REMOTE_ADDR'] = trim($forwarded_for_ips[0]);
}

// Define WP_SITEURL and WP_HOME if needed, potentially from env vars or dynamically
// Example: define( 'WP_HOME', get_env_var('WORDPRESS_HOME_URL') );
// Example: define( 'WP_SITEURL', get_env_var('WORDPRESS_SITE_URL') );


/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
        define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
// --- BEGIN ENV DEBUG SNIPPET ---
error_log("ENV DEBUG: WORDPRESS_DB_HOST=" . getenv('WORDPRESS_DB_HOST'));
error_log("ENV DEBUG: WORDPRESS_DB_USER=" . getenv('WORDPRESS_DB_USER'));
error_log("ENV DEBUG: WORDPRESS_DB_NAME=" . getenv('WORDPRESS_DB_NAME'));
// --- END ENV DEBUG SNIPPET ---
require_once ABSPATH . 'wp-settings.php';
