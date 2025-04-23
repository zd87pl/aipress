<?php
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

/** Database username */
define( 'DB_USER', get_env_var('WORDPRESS_DB_USER', 'root') );

/** Database password */
define( 'DB_PASSWORD', get_env_var('WORDPRESS_DB_PASSWORD', '') );

/** Database hostname */
define( 'DB_HOST', get_env_var('WORDPRESS_DB_HOST', 'localhost') );

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
require_once ABSPATH . 'wp-settings.php';
