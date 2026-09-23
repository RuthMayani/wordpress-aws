import json
import secrets
import socket
import ssl
import subprocess
import sys
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parents[1]
REGION = "us-east-1"


def terraform_output(name):
    result = subprocess.run(
        ["terraform", "-chdir=terraform", "output", "-raw", name],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def aws(service, operation, payload):
    import boto3
    from botocore.exceptions import ClientError

    client = boto3.client(service, region_name=REGION)
    method = getattr(client, operation.replace("-", "_"))

    try:
        return method(**payload)
    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "Unknown")
        raise RuntimeError(
            f"AWS {service} {operation} failed: {code}"
        ) from None


def connect_db(host, username, password, database=None):
    context = ssl.create_default_context(
        cafile="/tmp/wordpress-rds-ca.pem"
    )

    connection = pymysql.connections.Connection(
        host=host,
        user=username,
        password=password,
        database=database,
        ssl=context,
        charset="utf8mb4",
        autocommit=True,
        defer_connect=True,
        connect_timeout=15,
        read_timeout=30,
        write_timeout=30,
    )

    # Connect through the tunnel, but verify the real RDS hostname.
    tunnel = socket.create_connection(("127.0.0.1", 13306), timeout=15)
    try:
        connection.connect(sock=tunnel)
    except Exception:
        tunnel.close()
        raise
    return connection


def main():
    host = terraform_output("database_address")
    master_arn = terraform_output("database_master_secret_arn")
    app_arn = terraform_output("application_secret_arn")

    master = json.loads(aws(
        "secretsmanager", "get-secret-value",
        {"SecretId": master_arn},
    )["SecretString"])

    with connect_db(host, master["username"], master["password"]):
        print("Administrator connection verified over TLS.")

    metadata = aws(
        "secretsmanager", "describe-secret", {"SecretId": app_arn}
    )
    versions = metadata.get("VersionIdsToStages", {})
    has_current = any("AWSCURRENT" in stages for stages in versions.values())

    if has_current:
        app = json.loads(aws(
            "secretsmanager", "get-secret-value",
            {"SecretId": app_arn},
        )["SecretString"])

        if (
            app.get("username") != "wordpress_app"
            or app.get("host") != host
            or app.get("dbname") != "wordpress"
            or not app.get("password")
        ):
            raise RuntimeError("Existing application secret does not match this setup.")

        print("Reusing existing application credentials.")
    else:
        if versions:
            raise RuntimeError("Secret has versions but no current version; inspect before continuing.")

        salt_names = [
            "AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
            "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT",
        ]

        app = {
            "username": "wordpress_app",
            "password": secrets.token_hex(32),
            "host": host,
            "port": 3306,
            "dbname": "wordpress",
            "wordpress_salts": {
                name: secrets.token_hex(32) for name in salt_names
            },
        }

        # Save first so an interrupted setup can reuse the same password.
        aws("secretsmanager", "put-secret-value", {
            "SecretId": app_arn,
            "SecretString": json.dumps(app),
        })
        print("Application credentials saved in Secrets Manager.")

    with connect_db(host, master["username"], master["password"]) as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "CREATE USER IF NOT EXISTS %s@%s IDENTIFIED BY %s REQUIRE SSL",
                (app["username"], "%", app["password"]),
            )
            cursor.execute(
                "ALTER USER %s@%s IDENTIFIED BY %s REQUIRE SSL",
                (app["username"], "%", app["password"]),
            )
            cursor.execute(
                "GRANT ALL PRIVILEGES ON `wordpress`.* TO %s@%s",
                (app["username"], "%"),
            )

    with connect_db(
        host, app["username"], app["password"], "wordpress"
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute("SHOW SESSION STATUS LIKE 'Ssl_cipher'")
            cipher = cursor.fetchone()
            if not cipher or not cipher[1]:
                raise RuntimeError("Database connection is not encrypted.")
            cursor.execute("SELECT 1")
            if cursor.fetchone()[0] != 1:
                raise RuntimeError("Database validation failed.")

    print("WORDPRESS_DATABASE_SETUP_PASSED")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Avoid printing SQL statements or credential-bearing payloads.
        print(f"Setup failed: {type(error).__name__}.", file=sys.stderr)
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        elif error.args and isinstance(error.args[0], int):
            print(f"Error code: {error.args[0]}", file=sys.stderr)
        sys.exit(1)
