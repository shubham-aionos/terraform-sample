#!/bin/bash

exec > /var/log/user-data.log 2>&1
set -euxo pipefail

echo "=== DATABASE-BACKED USER DATA STARTED ==="

export AWS_REGION="${aws_region}"
export DB_SECRET_ARN="${db_secret_arn}"
export RUNTIME_S3_BUCKET="${runtime_s3_bucket}"
export RUNTIME_S3_KEY="${runtime_s3_key}"

mkdir -p /var/www/app /opt/app/vendor

cat > /opt/app/aws_signing.py <<'PY'
import datetime
import hashlib
import hmac
import json
import os
import urllib.parse
import urllib.request

REGION = os.environ["AWS_REGION"]
IMDS_BASE = "http://169.254.169.254/latest"

def _imds_token():
    request = urllib.request.Request(
        IMDS_BASE + "/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        return response.read().decode()

def _credentials():
    token = _imds_token()
    request = urllib.request.Request(
        IMDS_BASE + "/meta-data/iam/security-credentials/",
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        role = response.read().decode().strip()

    request = urllib.request.Request(
        IMDS_BASE + "/meta-data/iam/security-credentials/" + role,
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.loads(response.read())

def _signing_key(secret_key, date_stamp, region, service):
    k_date = hmac.new(("AWS4" + secret_key).encode(), date_stamp.encode(), hashlib.sha256).digest()
    k_region = hmac.new(k_date, region.encode(), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service.encode(), hashlib.sha256).digest()
    return hmac.new(k_service, b"aws4_request", hashlib.sha256).digest()

def signed_request(method, host, path, service, body=b"", extra_headers=None):
    credentials = _credentials()
    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(body).hexdigest()

    headers = {
        "host": host,
        "x-amz-date": amz_date,
        "x-amz-security-token": credentials["Token"],
        "x-amz-content-sha256": payload_hash,
    }
    if extra_headers:
        headers.update(extra_headers)

    canonical_headers = "".join(
        key.lower() + ":" + " ".join(value.strip().split()) + "\n"
        for key, value in sorted(headers.items())
    )
    signed_headers = ";".join(key.lower() for key in sorted(headers))
    canonical_request = "\n".join([method, path, "", canonical_headers, signed_headers, payload_hash])

    credential_scope = f"{date_stamp}/{REGION}/{service}/aws4_request"
    string_to_sign = "\n".join([
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        hashlib.sha256(canonical_request.encode()).hexdigest(),
    ])
    signature = hmac.new(
        _signing_key(credentials["SecretAccessKey"], date_stamp, REGION, service),
        string_to_sign.encode(),
        hashlib.sha256,
    ).hexdigest()

    headers["Authorization"] = (
        "AWS4-HMAC-SHA256 Credential=" + credentials["AccessKeyId"] + "/" + credential_scope
        + ", SignedHeaders=" + signed_headers + ", Signature=" + signature
    )

    request = urllib.request.Request(
        "https://" + host + path,
        data=body,
        method=method,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.read()

def get_s3_object(bucket, key):
    host = f"{bucket}.s3.{REGION}.amazonaws.com"
    path = "/" + "/".join(urllib.parse.quote(part, safe="") for part in key.split("/"))
    return signed_request("GET", host, path, "s3")

def get_secret(secret_arn):
    host = f"secretsmanager.{REGION}.amazonaws.com"
    body = json.dumps({"SecretId": secret_arn}, separators=(",", ":")).encode()
    response = signed_request(
        "POST",
        host,
        "/",
        "secretsmanager",
        body,
        {
            "content-type": "application/x-amz-json-1.1",
            "x-amz-target": "secretsmanager.GetSecretValue",
        },
    )
    return json.loads(json.loads(response)["SecretString"])
PY

cat > /opt/app/app.py <<'PY'
import html
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

from aws_signing import get_secret

SECRET_ARN = os.environ["DB_SECRET_ARN"]

def database_status():
    secret = get_secret(SECRET_ARN)
    with psycopg.connect(
        host=secret["host"],
        port=int(secret["port"]),
        dbname=secret.get("dbname", "appdb"),
        user=secret["username"],
        password=secret["password"],
        connect_timeout=5,
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS app_status (
                    id integer PRIMARY KEY,
                    message text NOT NULL,
                    updated_at timestamptz NOT NULL DEFAULT now()
                )
            """)
            cursor.execute("""
                INSERT INTO app_status (id, message)
                VALUES (1, 'Application is connected to PostgreSQL RDS')
                ON CONFLICT (id)
                DO UPDATE SET message = EXCLUDED.message, updated_at = now()
            """)
            cursor.execute("SELECT message, updated_at FROM app_status WHERE id = 1")
            return cursor.fetchone()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            message, updated_at = database_status()
            body = f"""<html>
  <head><title>Three Tier AWS App</title></head>
  <body>
    <h1>Hello from the AWS Three-Tier Architecture!</h1>
    <p>This page is running on an EC2 instance in a private subnet.</p>
    <h2>Database status: Connected</h2>
    <p>{html.escape(message)}</p>
    <p>Database last updated: {html.escape(str(updated_at))}</p>
  </body>
</html>
"""
            status = 200
        except Exception as exc:
            body = f"""<html>
  <head><title>Three Tier AWS App</title></head>
  <body>
    <h1>Hello from the AWS Three-Tier Architecture!</h1>
    <h2>Database status: ERROR</h2>
    <p>{html.escape(str(exc))}</p>
  </body>
</html>
"""
            status = 503

        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format_string, *args):
        print(format_string % args)

ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
PY

echo "=== DOWNLOADING OFFLINE PSYCOPG RUNTIME FROM S3 ==="
python3 - <<'PY'
import os
import sys
sys.path.insert(0, "/opt/app")
from aws_signing import get_s3_object

data = get_s3_object(os.environ["RUNTIME_S3_BUCKET"], os.environ["RUNTIME_S3_KEY"])
open("/tmp/psycopg-runtime.zip", "wb").write(data)
print(f"Downloaded runtime bundle: {len(data)} bytes")
PY

echo "=== EXTRACTING PSYCOPG RUNTIME ==="
python3 - <<'PY'
import zipfile
with zipfile.ZipFile("/tmp/psycopg-runtime.zip") as archive:
    archive.extractall("/opt/app/vendor")
PY

echo "=== CHECKING PSYCOPG ==="
PYTHONPATH=/opt/app/vendor python3 -c "import psycopg; print('psycopg', psycopg.__version__)"

cat > /etc/three-tier-app.env <<EOF
AWS_REGION=${aws_region}
DB_SECRET_ARN=${db_secret_arn}
RUNTIME_S3_BUCKET=${runtime_s3_bucket}
RUNTIME_S3_KEY=${runtime_s3_key}
PYTHONPATH=/opt/app/vendor:/opt/app
EOF

echo "=== STARTING DATABASE-BACKED APPLICATION ==="
set -a
source /etc/three-tier-app.env
set +a
nohup /usr/bin/python3 /opt/app/app.py > /var/log/app-server.log 2>&1 &

sleep 3

echo "=== CHECKING LOCAL APPLICATION ==="
curl -i http://127.0.0.1:8080/ || true

echo "=== CHECKING PORT 8080 ==="
ss -lntp | grep 8080 || true

echo "=== DATABASE-BACKED USER DATA FINISHED ==="
