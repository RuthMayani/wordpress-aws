#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p dist

tar --sort=name \
  --mtime='UTC 2020-01-01' \
  --owner=0 --group=0 --numeric-owner \
  -czf dist/wordpress-runtime.tar.gz \
  -C docker/production \
  compose.yml wp-config.php healthz.php php.ini nginx.conf rds-ca.pem

echo "Deployment package created."
