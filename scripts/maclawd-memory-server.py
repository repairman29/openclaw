#!/usr/bin/env python3
"""Minimal memory service for Maclawd stack. Serves /health on port 8002."""

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys

HOST = "127.0.0.1"
PORT = 8002


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health" or self.path == "/health/":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # quiet by default


def main():
    server = HTTPServer((HOST, PORT), HealthHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
