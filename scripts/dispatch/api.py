"""Dispatch API server using only http.server."""
from __future__ import annotations
import json
import os
import sys
import uuid
from http.server import HTTPServer, BaseHTTPRequestHandler


class DispatchHandler(BaseHTTPRequestHandler):
    """HTTP handler for the dispatch API."""

    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        """Suppress default logging."""

    def _send_json(self, status: int, body: dict):
        """Send a JSON response."""
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _require_auth(self) -> bool:
        """Check authorization header; return True if valid."""
        token = os.environ.get("HARNESS_API_TOKEN", "")
        if not token:
            return False
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {token}":
            return True
        self._send_json(401, {"error": "unauthorized"})
        return False

    def do_POST(self):
        """Handle POST /runs."""
        if not self._require_auth():
            return

        if self.path != "/runs":
            self._send_json(404, {"error": "not found"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = {}
        if content_length > 0:
            raw = self.rfile.read(content_length)
            try:
                body = json.loads(raw.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                self._send_json(400, {"error": "invalid json"})
                return

        repo = body.get("repo")
        spec = body.get("spec")
        strategy = body.get("strategy", "build-converge")
        idempotency_key = body.get("idempotency_key")

        if not repo or not spec:
            self._send_json(400, {"error": "missing required fields: repo and spec are required"})
            return

        if not idempotency_key:
            idempotency_key = str(uuid.uuid4())

        from dispatcher import launch_run

        ledger_path = os.environ.get("HARNESS_LEDGER_PATH", "")
        registry_path = os.environ.get("HARNESS_REGISTRY_PATH", "")
        image = os.environ.get("HARNESS_WORKER_IMAGE", "img:latest")
        namespace = os.environ.get("HARNESS_NAMESPACE", "harness-fleet")

        result = launch_run(
            repo,
            spec,
            strategy,
            idempotency_key,
            ledger_path=ledger_path,
            image=image,
            namespace=namespace,
            registry_path=registry_path,
        )

        status_code = 202 if result.get("launched") else 200
        self._send_json(
            status_code,
            {
                "event_id": idempotency_key,
                "status": "launched" if result.get("launched") else "duplicate",
                "exit_code": result.get("exit_code"),
            },
        )

    def do_GET(self):
        """Handle GET /runs and GET /runs/<id> and GET /runs/<id>/evidence."""
        if not self._require_auth():
            return

        if self.path == "/runs":
            from dispatcher import read_runs

            registry_path = os.environ.get("HARNESS_REGISTRY_PATH", "")
            runs = read_runs(registry_path)
            self._send_json(200, {"runs": runs})
            return

        if self.path.startswith("/runs/"):
            parts = self.path.split("/")
            if len(parts) == 3:
                run_id = parts[2]
                from dispatcher import get_run

                registry_path = os.environ.get("HARNESS_REGISTRY_PATH", "")
                run = get_run(registry_path, run_id)
                if run:
                    self._send_json(200, run)
                else:
                    self._send_json(404, {"error": "run not found"})
                return

            if len(parts) == 4 and parts[3] == "evidence":
                self._send_json(501, {"error": "fetch_evidence is not implemented"})
                return

        self._send_json(404, {"error": "not found"})

    def do_DELETE(self):
        """Handle DELETE /runs/<id>."""
        if not self._require_auth():
            return

        if self.path.startswith("/runs/"):
            parts = self.path.split("/")
            if len(parts) == 3:
                run_id = parts[2]
                from dispatcher import get_run

                registry_path = os.environ.get("HARNESS_REGISTRY_PATH", "")
                run = get_run(registry_path, run_id)
                if not run:
                    self._send_json(404, {"error": "run not found"})
                    return

                job_name = run.get("job_name", f"run-{run_id}")
                namespace = os.environ.get("HARNESS_NAMESPACE", "harness-fleet")
                kubectl = os.environ.get("HARNESS_KUBECTL", "kubectl")

                import subprocess

                try:
                    subprocess.run(
                        [kubectl, "delete", "job", job_name, "-n", namespace],
                        capture_output=True,
                        timeout=30,
                    )
                except Exception:
                    pass

                self._send_json(202, {"status": "cancellation initiated"})
                return

        self._send_json(404, {"error": "not found"})


def serve(port: int):
    """Start the HTTP server on the given port."""
    token = os.environ.get("HARNESS_API_TOKEN", "")
    if not token:
        print("error: HARNESS_API_TOKEN is required", file=sys.stderr)
        sys.exit(1)

    server = HTTPServer(("0.0.0.0", port), DispatchHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
