#!/bin/bash

exec > /var/log/user-data.log 2>&1
set -x

echo "=== USER DATA STARTED ==="

mkdir -p /var/www/app

cat > /var/www/app/index.html <<'HTML'
<html>
  <head>
    <title>Three Tier AWS App</title>
  </head>
  <body>
    <h1>Hello from the AWS Three-Tier Architecture!</h1>
    <p>This page is running on an EC2 instance in a private subnet.</p>
  </body>
</html>
HTML

echo "=== CHECKING PYTHON ==="
which python3
python3 --version

echo "=== STARTING APPLICATION ==="
cd /var/www/app
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /var/log/app-server.log 2>&1 &

sleep 2

echo "=== CHECKING LOCAL APPLICATION ==="
curl -v http://127.0.0.1:8080/ || true

echo "=== CHECKING PORT 8080 ==="
ss -lntp | grep 8080 || true

echo "=== USER DATA FINISHED ==="
