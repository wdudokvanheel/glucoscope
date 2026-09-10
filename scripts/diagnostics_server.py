#!/usr/bin/env python3
"""Small local HTTP receiver for GlucoScope diagnostic exports."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from uuid import uuid4


MAX_BODY_BYTES = 1024 * 1024
DEFAULT_OUTPUT_DIR = Path("/tmp/glucoscope-diagnostics")


class DiagnosticsHandler(BaseHTTPRequestHandler):
    server_version = "GlucoScopeDiagnostics/1.0"

    def _json(self, status: int, payload: dict[str, str]) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path != "/health":
            self._json(404, {"error": "not found"})
            return
        self._json(200, {"status": "ok"})

    def do_POST(self) -> None:
        if self.path != "/diagnostics":
            self._json(404, {"error": "not found"})
            return

        content_type = self.headers.get_content_type()
        if content_type != "text/plain":
            self._json(415, {"error": "content type must be text/plain"})
            return

        length_header = self.headers.get("Content-Length")
        if length_header is None:
            self._json(411, {"error": "content length required"})
            return
        try:
            content_length = int(length_header)
        except ValueError:
            self._json(400, {"error": "invalid content length"})
            return
        if content_length < 0:
            self._json(400, {"error": "invalid content length"})
            return
        if content_length > MAX_BODY_BYTES:
            self._json(413, {"error": "diagnostics export exceeds 1 MiB"})
            return

        body = self.rfile.read(content_length)
        try:
            body.decode("utf-8")
        except UnicodeDecodeError:
            self._json(400, {"error": "diagnostics export must be UTF-8"})
            return

        output_dir: Path = self.server.output_dir  # type: ignore[attr-defined]
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        filename = f"diagnostics-{timestamp}-{uuid4().hex[:8]}.txt"
        output_path = output_dir / filename
        fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as output_file:
            output_file.write(body)

        print(f"Saved {len(body)} bytes to {output_path}", flush=True)
        self._json(201, {"saved": filename})

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.address_string()} - {format % args}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()

    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), DiagnosticsHandler)
    server.output_dir = args.output_dir
    print(
        f"GlucoScope diagnostics receiver listening on {args.host}:{args.port}; "
        f"saving to {args.output_dir}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
