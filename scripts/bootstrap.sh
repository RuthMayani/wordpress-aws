#!/bin/bash
set -euo pipefail

exec > >(tee -a /var/log/wordpress-bootstrap.log) 2>&1

echo "Starting server preparation"

retry() {
  local attempt
  for attempt in $(seq 1 12); do
    if "$@"; then
      return 0
    fi
    echo "Retrying operation in 15 seconds..."
    sleep 15
  done
  return 1
}

systemctl enable --now amazon-ssm-agent

retry dnf install -y docker amazon-efs-utils jq python3

systemctl enable --now docker

mkdir -p /srv/wordpress/content
mkdir -p /opt/wordpress

cat > /opt/wordpress/infrastructure.env <<'CONFIG'
AWS_REGION=${aws_region}
DB_HOST=${database_address}
APP_SECRET_ARN=${application_secret_arn}
EFS_ID=${efs_id}
EFS_ACCESS_POINT=${efs_access_point}
CONFIG

chmod 600 /opt/wordpress/infrastructure.env

EFS_ENTRY="${efs_id}:/ /srv/wordpress/content efs _netdev,tls,iam,accesspoint=${efs_access_point} 0 0"

if ! grep -Fq "$EFS_ENTRY" /etc/fstab; then
  printf '%s\n' "$EFS_ENTRY" >> /etc/fstab
fi

systemctl daemon-reload
retry mount /srv/wordpress/content
mountpoint -q /srv/wordpress/content

PROBE_FILE=$(mktemp /srv/wordpress/content/.bootstrap-check.XXXXXX)
printf 'EFS write check passed\n' > "$PROBE_FILE"
rm "$PROBE_FILE"

docker info > /dev/null

touch /opt/wordpress/bootstrap-complete
echo "Server preparation complete: Docker running and EFS writable"

# Install the same application release on replacement servers.
printf '%s' '${runtime_installer_b64}' |
  base64 -d > /opt/wordpress/install-runtime.sh

chmod 0750 /opt/wordpress/install-runtime.sh

bash /opt/wordpress/install-runtime.sh \
  '${runtime_package_uri}' \
  '${runtime_package_sha}'
