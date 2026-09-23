<?php
$credentials = json_decode(
    file_get_contents('/run/secrets/app.json'),
    true,
    512,
    JSON_THROW_ON_ERROR
);

define('DB_NAME', $credentials['dbname']);
define('DB_USER', $credentials['username']);
define('DB_PASSWORD', $credentials['password']);
define('DB_HOST', $credentials['host'] . ':3306');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

define('MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL);

foreach ($credentials['wordpress_salts'] as $name => $value) {
    define($name, $value);
}
unset($credentials);

$table_prefix = 'wp_';

define('WP_DEBUG', false);
define('WP_ENVIRONMENT_TYPE', 'production');
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('AUTOMATIC_UPDATER_DISABLED', true);

/* Trust the forwarded scheme only through our controlled proxy chain. */
if (
    isset($_SERVER['HTTP_X_FORWARDED_PROTO'])
    && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https'
) {
    $_SERVER['HTTPS'] = 'on';
}

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
