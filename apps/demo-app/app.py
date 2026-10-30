"""Demo application used as the pilot for the deploy platform.

Exposes a deep health endpoint, structured JSON logs and request correlation.
"""

from __future__ import annotations

import json
import os
import signal
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

VERSION = os.environ.get("APP_VERSION", "dev")
PORT = int(os.environ.get("APP_PORT", "8080"))
DEPENDENCY_URL = os.environ.get("DEPENDENCY_URL", "")
DEPENDENCY_TIMEOUT = float(os.environ.get("DEPENDENCY_TIMEOUT", "2"))


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def request_id(value: str | None) -> str:
    return value if value else str(uuid.uuid4())


def log_event(level: str, message: str, req_id: str, **fields: object) -> str:
    record = {
        "timestamp": utc_now(),
        "level": level,
        "message": message,
        "request_id": req_id,
        "version": VERSION,
    }
    record.update(fields)
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
    print(line, flush=True)
    return line


def check_dependency(url: str = DEPENDENCY_URL, timeout: float = DEPENDENCY_TIMEOUT) -> dict:
    if not url:
        return {"name": "dependency", "status": "skipped", "latency_ms": 0}
    started = time.monotonic()
    try:
        with urlopen(url, timeout=timeout) as response:
            healthy = 200 <= response.status < 400
        status = "up" if healthy else "down"
        error = None if healthy else f"http_{response.status}"
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        status = "down"
        error = type(exc).__name__
    latency = round((time.monotonic() - started) * 1000, 1)
    result = {"name": "dependency", "status": status, "latency_ms": latency}
    if error:
        result["error"] = error
    return result


def build_health(checks: list[dict]) -> tuple[int, dict]:
    unhealthy = any(check["status"] == "down" for check in checks)
    payload = {
        "status": "unhealthy" if unhealthy else "healthy",
        "version": VERSION,
        "checks": checks,
    }
    return (503 if unhealthy else 200), payload


class Handler(BaseHTTPRequestHandler):
    server_version = "demo-app"
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        started = time.monotonic()
        req_id = request_id(self.headers.get("X-Request-ID"))
        path = self.path.split("?", 1)[0]

        if path == "/health":
            code, payload = build_health([check_dependency()])
            if code != 200:
                log_event("error", "health check failed", req_id, path=path, code=code, checks=payload["checks"])
        elif path == "/":
            code, payload = 200, {"service": "demo-app", "version": VERSION}
        else:
            code, payload = 404, {"message": "not found"}

        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Request-ID", req_id)
        self.end_headers()
        self.wfile.write(body)

        if path != "/health" or code != 200:
            log_event(
                "info" if code < 500 else "error",
                "request",
                req_id,
                method="GET",
                path=path,
                code=code,
                duration_ms=round((time.monotonic() - started) * 1000, 1),
            )

    def log_message(self, fmt: str, *args: object) -> None:
        return


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)

    def shutdown(signum: int, frame: object) -> None:
        log_event("info", "shutting down", "system", signal=signum)
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    log_event("info", "starting demo-app", "system", port=PORT, version=VERSION)

    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        while worker.is_alive():
            worker.join(timeout=1)
    except KeyboardInterrupt:
        server.shutdown()
    server.server_close()
    sys.exit(0)


if __name__ == "__main__":
    main()
