"""Tiny web app for the HA portfolio project.

Endpoints
  /        HTML page showing which instance and AZ served the request
  /health  liveness for the load balancer. Deliberately does NOT touch the
           database: if the DB fails over, instances must stay "healthy" or
           the ASG would replace every instance at once.
  /db      connects to PostgreSQL and reports latency, server time and version

Configuration comes from environment variables written by EC2 user data.
The DB password is read from Secrets Manager at runtime, never from disk.
"""

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("APP_PORT", "8080"))
INSTANCE_ID = os.environ.get("INSTANCE_ID", "local")
AZ = os.environ.get("AVAILABILITY_ZONE", "local")
REGION = os.environ.get("AWS_REGION", "us-east-1")
DB_HOST = os.environ.get("DB_HOST", "")
DB_NAME = os.environ.get("DB_NAME", "app")
DB_SECRET_ARN = os.environ.get("DB_SECRET_ARN", "")

SECRET_TTL_SECONDS = 300
_secret_cache = {"value": None, "fetched_at": 0.0}


def db_credentials(force_refresh=False):
    """Fetch {username, password} from Secrets Manager, cached for 5 minutes.

    RDS rotates the managed password, so callers retry once with
    force_refresh=True when authentication fails.
    """
    fresh = time.monotonic() - _secret_cache["fetched_at"] < SECRET_TTL_SECONDS
    if _secret_cache["value"] and fresh and not force_refresh:
        return _secret_cache["value"]

    import boto3  # imported lazily so /health works even if boto3 is missing

    client = boto3.client("secretsmanager", region_name=REGION)
    secret = json.loads(client.get_secret_value(SecretId=DB_SECRET_ARN)["SecretString"])
    _secret_cache["value"] = secret
    _secret_cache["fetched_at"] = time.monotonic()
    return secret


def _query_db(creds):
    import psycopg

    with psycopg.connect(
        host=DB_HOST,
        dbname=DB_NAME,
        user=creds["username"],
        password=creds["password"],
        sslmode="require",
        connect_timeout=3,
    ) as conn:
        return conn.execute(
            "select now()::text, inet_server_addr()::text, version()"
        ).fetchone()


def check_db():
    if not DB_HOST or not DB_SECRET_ARN:
        return 503, {"ok": False, "error": "DB_HOST / DB_SECRET_ARN not configured"}

    start = time.monotonic()
    try:
        try:
            row = _query_db(db_credentials())
        except Exception as exc:  # password may have rotated: refresh once
            if "password authentication failed" not in str(exc):
                raise
            row = _query_db(db_credentials(force_refresh=True))
    except Exception as exc:
        return 503, {
            "ok": False,
            "error": type(exc).__name__,
            "detail": str(exc)[:300],
            "instance": INSTANCE_ID,
            "az": AZ,
        }

    return 200, {
        "ok": True,
        "latency_ms": round((time.monotonic() - start) * 1000, 1),
        "db_time": row[0],
        "db_server_ip": row[1],
        "db_version": row[2].split(",")[0],
        "instance": INSTANCE_ID,
        "az": AZ,
    }


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>ha-web-app</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{{font-family:system-ui,sans-serif;max-width:40rem;margin:4rem auto;padding:0 1rem;color:#1f2933}}
 code{{background:#f0f2f5;padding:.1rem .35rem;border-radius:4px}}
 .card{{border:1px solid #d9dee5;border-radius:10px;padding:1.25rem 1.5rem;margin-top:1.5rem}}
</style></head><body>
<h1>ha-web-app</h1>
<p>Served by a multi-AZ Auto Scaling group behind a load balancer.</p>
<div class="card">
 <p>Instance <code>{instance}</code></p>
 <p>Availability Zone <code>{az}</code></p>
</div>
<p>Refresh to watch requests move between instances. Database check: <a href="/db">/db</a></p>
</body></html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "ha-web-app/1.0"

    def _send(self, status, body, content_type="application/json"):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802 (http.server naming)
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._send(200, {"status": "ok", "instance": INSTANCE_ID, "az": AZ})
        elif path == "/db":
            status, body = check_db()
            self._send(status, body)
        elif path == "/":
            html = PAGE.format(instance=INSTANCE_ID, az=AZ)
            self._send(200, html, "text/html; charset=utf-8")
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):  # one compact line per request to journald
        print(f"{self.address_string()} {self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    print(f"listening on :{PORT} instance={INSTANCE_ID} az={AZ}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
