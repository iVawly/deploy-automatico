import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import app


class HealthyHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, fmt, *args):
        return


class TestHealth(unittest.TestCase):
    def test_healthy_without_dependency(self):
        code, payload = app.build_health([app.check_dependency(url="")])
        self.assertEqual(code, 200)
        self.assertEqual(payload["status"], "healthy")
        self.assertEqual(payload["checks"][0]["status"], "skipped")

    def test_unhealthy_when_dependency_is_down(self):
        checks = [app.check_dependency(url="http://127.0.0.1:1/health", timeout=0.2)]
        code, payload = app.build_health(checks)
        self.assertEqual(code, 503)
        self.assertEqual(payload["status"], "unhealthy")
        self.assertEqual(payload["checks"][0]["status"], "down")

    def test_healthy_when_dependency_is_up(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), HealthyHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_address[1]}/health"
            code, payload = app.build_health([app.check_dependency(url=url, timeout=1)])
            self.assertEqual(code, 200)
            self.assertEqual(payload["checks"][0]["status"], "up")
        finally:
            server.shutdown()
            server.server_close()

    def test_vendor_version_is_reported(self):
        code, payload = app.build_health([])
        self.assertEqual(code, 200)
        self.assertEqual(payload["version"], app.VERSION)


class TestCorrelation(unittest.TestCase):
    def test_existing_request_id_is_reused(self):
        self.assertEqual(app.request_id("abc-123"), "abc-123")

    def test_missing_request_id_is_generated(self):
        first = app.request_id(None)
        second = app.request_id(None)
        self.assertNotEqual(first, second)
        self.assertEqual(len(first), 36)

    def test_log_record_has_required_fields(self):
        line = app.log_event("info", "request", "req-1", path="/", code=200)
        record = json.loads(line)
        for field in ("timestamp", "level", "message", "request_id", "version"):
            self.assertIn(field, record)
        self.assertEqual(record["request_id"], "req-1")
        self.assertEqual(record["code"], 200)


if __name__ == "__main__":
    unittest.main()
