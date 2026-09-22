import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

import boto3
import psycopg


SECRET_NAME = "three-tier/database"
PORT = 8080


def get_database_credentials():
    client = boto3.client("secretsmanager")

    response = client.get_secret_value(
        SecretId=SECRET_NAME
    )

    return json.loads(response["SecretString"])


def check_database():
    credentials = get_database_credentials()

    connection = psycopg.connect(
        host=credentials["host"],
        port=credentials["port"],
        dbname=credentials["database"],
        user=credentials["username"],
        password=credentials["password"],
        connect_timeout=5,
    )

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1;")
            result = cursor.fetchone()

        return result[0] == 1

    finally:
        connection.close()


class ApplicationHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path != "/":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")
            return

        try:
            database_ok = check_database()

            if database_ok:
                body = """
<html>
<head>
    <title>Three Tier AWS App</title>
</head>
<body>
    <h1>Hello from the AWS Three-Tier Architecture!</h1>
    <p>Application status: OK</p>
    <p>Database status: Connected</p>
    <p>Database query: Successful</p>
</body>
</html>
"""
                status = 200

            else:
                body = """
<html>
<body>
    <h1>Database check failed</h1>
</body>
</html>
"""
                status = 500

        except Exception as error:
            print(f"Database error: {error}")

            body = """
<html>
<head>
    <title>Three Tier AWS App</title>
</head>
<body>
    <h1>Hello from the AWS Three-Tier Architecture!</h1>
    <p>Application status: ERROR</p>
    <p>Database status: Connection failed</p>
</body>
</html>
"""
            status = 500

        response = body.encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), ApplicationHandler)

    print(f"Application listening on port {PORT}")

    server.serve_forever()
