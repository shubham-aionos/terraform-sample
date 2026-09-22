#!/bin/bash

exec > /var/log/user-data.log 2>&1
set -x

echo "=== USER DATA STARTED ==="

APP_DIR="/var/www/app"
ARTIFACT="/tmp/application.tar.gz"

mkdir -p "$APP_DIR"

echo "=== CHECKING PYTHON ==="
which python3
python3 --version

echo "=== CHECKING AWS CLI ==="
which aws
aws --version

echo "=== DOWNLOADING APPLICATION ARTIFACT ==="

aws s3 cp \
  "s3://${application_artifact_bucket}/${application_artifact_key}" \
  "$ARTIFACT"

echo "=== EXTRACTING APPLICATION ==="

rm -rf "$APP_DIR"/*
tar -xzf "$ARTIFACT" -C "$APP_DIR"

echo "=== APPLICATION FILES ==="
find "$APP_DIR" -maxdepth 2 -type f -print

echo "=== STARTING APPLICATION ==="

cd "$APP_DIR"

export PYTHONPATH="$APP_DIR/python-deps"

nohup python3 app.py \
  > /var/log/app-server.log 2>&1 &

sleep 5

echo "=== CHECKING LOCAL APPLICATION ==="

curl -v http://127.0.0.1:8080/ || true

echo "=== CHECKING PORT 8080 ==="

ss -lntp | grep 8080 || true

echo "=== USER DATA FINISHED ==="
