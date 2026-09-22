import html
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

from aws_signing import get_secret

SECRET_ARN = os.environ["DB_SECRET_ARN"]
PORT = 8080


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
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS app_status (
                    id integer PRIMARY KEY,
                    message text NOT NULL,
                    updated_at timestamptz NOT NULL DEFAULT now()
                )
                """
            )
            cursor.execute(
                """
                INSERT INTO app_status (id, message)
                VALUES (1, 'Application is connected to PostgreSQL RDS')
                ON CONFLICT (id)
                DO UPDATE SET message = EXCLUDED.message, updated_at = now()
                """
            )
            cursor.execute(
                "SELECT message, updated_at FROM app_status WHERE id = 1"
            )
            message, updated_at = cursor.fetchone()
            return message, updated_at


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            message, updated_at = database_status()
            body = f"""<html>
  <head>
    <title>Three Tier AWS App</title>
  </head>
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


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
