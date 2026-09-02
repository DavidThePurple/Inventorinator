import html
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


CONNECTOR_VERSION = 2
SCHEMA_VERSION = 13
PUBLIC_URL = os.environ["SUPABASE_PUBLIC_URL"].rstrip("/")
PUBLISHABLE_KEY = os.environ["SUPABASE_PUBLISHABLE_KEY"]


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, content_type, body):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self._send(200, "application/json", '{"status":"ok"}')
            return
        if self.path == "/.well-known/inventorinator":
            self._send(
                200,
                "application/json",
                json.dumps(
                    {
                        "provider": "supabase",
                        "connector_version": CONNECTOR_VERSION,
                        "schema_version": SCHEMA_VERSION,
                        "supabase_url": PUBLIC_URL,
                        "publishable_key": PUBLISHABLE_KEY,
                    }
                ),
            )
            return
        if self.path == "/":
            self._send(
                200,
                "text/html; charset=utf-8",
                """<!doctype html><html><head><meta name=viewport content='width=device-width'>
                <title>Inventorinator Connector</title><style>
                body{font:16px system-ui;background:#11151f;color:#eef0f6;max-width:680px;margin:12vh auto;padding:24px}
                main{background:#202531;border:1px solid #343b4d;border-radius:20px;padding:28px}
                code{background:#11151f;padding:4px 8px;border-radius:7px}</style></head>
                <body><main><h1>Inventorinator Connector</h1><p>Ready.</p>
                <p>In Inventorinator, choose <b>Supabase</b> and enter:</p>
                <p>Server address</p><code>""" + html.escape(PUBLIC_URL) + """</code>
                <p>Publishable key</p><code style='word-break:break-all'>""" + html.escape(PUBLISHABLE_KEY) + """</code>
                <p>The connector has already installed the required database schema.</p></main></body></html>""",
            )
            return
        self._send(404, "application/json", '{"error":"not found"}')

    def log_message(self, format, *args):
        print("connector:", format % args)


ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
