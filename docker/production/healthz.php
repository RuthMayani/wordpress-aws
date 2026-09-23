<?php
header('Content-Type: text/plain');
header('Cache-Control: no-store');

define('SHORTINIT', true);

try {
    require __DIR__ . '/wp-load.php';

    global $wpdb;
    $wpdb->suppress_errors(true);

    if ((string) $wpdb->get_var('SELECT 1') !== '1') {
        throw new RuntimeException('Database unavailable');
    }

    $tls = $wpdb->get_row(
        "SHOW SESSION STATUS LIKE 'Ssl_cipher'",
        ARRAY_N
    );

    if (empty($tls[1])) {
        throw new RuntimeException('Database TLS unavailable');
    }

    if (!is_readable(__DIR__ . '/wp-content')) {
        throw new RuntimeException('Content unavailable');
    }

    http_response_code(200);
    echo "ok\n";
} catch (Throwable $error) {
    http_response_code(503);
    echo "unavailable\n";
}
