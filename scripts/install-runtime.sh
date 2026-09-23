#!/usr/bin/env bash
set -euo pipefail

PACKAGE_URI="$1"
PACKAGE_SHA="$2"

source /opt/wordpress/infrastructure.env
export AWS_DEFAULT_REGION="$AWS_REGION"

mountpoint -q /srv/wordpress/content

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Install a specific Compose version and verify its download.
if ! docker compose version >/dev/null 2>&1; then
  COMPOSE_VERSION="v2.39.4"
  COMPOSE_BASE="https://github.com/docker/compose/releases/download/$COMPOSE_VERSION"

  curl -fL --retry 5 \
    "$COMPOSE_BASE/docker-compose-linux-x86_64" \
    -o "$WORK_DIR/docker-compose-linux-x86_64"

  curl -fL --retry 5 \
    "$COMPOSE_BASE/docker-compose-linux-x86_64.sha256" \
    -o "$WORK_DIR/compose.sha256"

  (
    cd "$WORK_DIR"
    EXPECTED=$(awk 'NR == 1 {print $1}' compose.sha256)
    printf '%s  docker-compose-linux-x86_64\n' "$EXPECTED" |
      sha256sum --check
  )

  install -d /usr/local/lib/docker/cli-plugins
  install -m 0755 "$WORK_DIR/docker-compose-linux-x86_64" \
    /usr/local/lib/docker/cli-plugins/docker-compose
fi

# Download and verify our application package.
aws s3 cp "$PACKAGE_URI" "$WORK_DIR/runtime.tar.gz" --only-show-errors

printf '%s  %s\n' "$PACKAGE_SHA" "$WORK_DIR/runtime.tar.gz" |
  sha256sum --check

install -d -m 0755 /opt/wordpress/runtime
tar --no-same-owner -xzf "$WORK_DIR/runtime.tar.gz" \
  -C /opt/wordpress/runtime

chmod 0644 /opt/wordpress/runtime/*

# Fetch credentials without printing them.
cat > /usr/local/sbin/wordpress-fetch-secret <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
umask 077

source /opt/wordpress/infrastructure.env
install -d -m 0750 -o root -g 33 /run/wordpress

SECRET_TMP=$(mktemp /run/wordpress/.app.XXXXXX)
trap 'rm -f "$SECRET_TMP"' EXIT

FETCHED=false
for attempt in $(seq 1 12); do
  if aws secretsmanager get-secret-value \
    --secret-id "$APP_SECRET_ARN" \
    --region "$AWS_REGION" \
    --query SecretString \
    --output text > "$SECRET_TMP"; then
    FETCHED=true
    break
  fi
  sleep 10
done

if [ "$FETCHED" != true ]; then
  echo "Unable to retrieve application credentials." >&2
  exit 1
fi

jq -e '
  .username == "wordpress_app"
  and .dbname == "wordpress"
  and (.password | type == "string")
  and (.host | type == "string")
  and (.wordpress_salts | length == 8)
' "$SECRET_TMP" >/dev/null

chown root:33 "$SECRET_TMP"
chmod 0440 "$SECRET_TMP"
mv -f "$SECRET_TMP" /run/wordpress/app.json
SCRIPT

chmod 0750 /usr/local/sbin/wordpress-fetch-secret

cat > /etc/systemd/system/wordpress-credentials.service <<'UNIT'
[Unit]
Description=Retrieve WordPress application credentials
Wants=network-online.target
After=network-online.target
Before=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wordpress-fetch-secret
RemainAfterExit=yes
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

# Require EFS and credentials before Docker starts after a reboot.
install -d /etc/systemd/system/docker.service.d

cat > /etc/systemd/system/docker.service.d/wordpress.conf <<'UNIT'
[Unit]
Requires=wordpress-credentials.service
After=wordpress-credentials.service
RequiresMountsFor=/srv/wordpress/content
UNIT

cat > /etc/systemd/system/wordpress.service <<'UNIT'
[Unit]
Description=WordPress and Nginx containers
Requires=docker.service wordpress-credentials.service
After=docker.service wordpress-credentials.service network-online.target
RequiresMountsFor=/srv/wordpress/content

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/wordpress/runtime
ExecStart=/usr/bin/docker compose -f compose.yml up -d --force-recreate --remove-orphans
ExecStop=/usr/bin/docker compose -f compose.yml stop
TimeoutStartSec=900
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable wordpress-credentials.service wordpress.service
systemctl restart wordpress-credentials.service
systemctl restart docker

cd /opt/wordpress/runtime
docker compose config --quiet
docker compose pull --quiet

# Seed shared content once, with a lock shared between the servers.
(
  flock -w 300 9
  if [ ! -f /srv/wordpress/content/.content-seeded ]; then
    docker run --rm --user 33:33 \
      --entrypoint sh \
      -v /srv/wordpress/content:/shared \
      wordpress:php8.3-apache \
      -c 'cp -an /usr/src/wordpress/wp-content/. /shared/'
    touch /srv/wordpress/content/.content-seeded
  fi
) 9>/srv/wordpress/content/.seed.lock

systemctl restart wordpress.service

# Verify the application and its encrypted database connection.
for attempt in $(seq 1 90); do
  if curl -fsS --max-time 10 http://127.0.0.1/healthz.php \
    2>/dev/null | grep -qx 'ok'; then
    echo "WORDPRESS_RUNTIME_HEALTH_PASSED"
    exit 0
  fi
  sleep 5
done

echo "Application health check failed. Recent container logs:" >&2
docker compose logs --tail=40
exit 1
