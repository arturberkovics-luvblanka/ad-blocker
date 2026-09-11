#!/usr/bin/env python3
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        if self.path.split("?", 1)[0] in {"/page.html", "/child.html"}:
            self.send_header(
                "Content-Security-Policy",
                "default-src 'none'; script-src 'none'; style-src 'none'; frame-src 'self'; connect-src 'none'",
            )
        super().end_headers()

    def log_message(self, format, *args):
        pass


if len(sys.argv) != 2:
    raise SystemExit("usage: server.py <port-file>")

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
Path(sys.argv[1]).write_text(str(server.server_port), encoding="utf-8")
try:
    server.serve_forever()
finally:
    server.server_close()
