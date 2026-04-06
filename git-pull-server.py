#!/usr/bin/env python3
"""Minimal HTTP server exposing POST /git/pull for on-demand vault sync."""

import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

VAULT = os.environ.get("OBSIDIAN_VAULT_PATH", "/vaults/default")
PORT = 27125


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/git/pull":
            result = subprocess.run(
                ["git", "pull", "--rebase", "--autostash"],
                cwd=VAULT,
                capture_output=True,
                text=True,
            )
            body = (result.stdout + result.stderr).encode()
            status = 200 if result.returncode == 0 else 500
            self.send_response(status)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):  # suppress access logs
        pass


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[git-pull-server] listening on port {PORT}", flush=True)
    server.serve_forever()
