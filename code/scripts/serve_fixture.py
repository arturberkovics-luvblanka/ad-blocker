#!/usr/bin/env python3
"""A local-only deterministic fixture; no requests go to an advertising service."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

FIXTURE = Path(__file__).resolve().parents[1] / "tests/fixture"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(FIXTURE), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        if self.path.split("?", 1)[0] == "/main-world-csp.html":
            self.send_header("Content-Security-Policy", "script-src 'none'; style-src 'unsafe-inline'")
        super().end_headers()


if __name__ == "__main__":
    try:
        server = ThreadingHTTPServer(("127.0.0.1", 8765), Handler)
    except OSError as error:
        raise SystemExit(f"A tesztszerver nem indult el: {error}")
    print("Tesztoldal: http://127.0.0.1:8765/ — leállítás: Ctrl+C", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
