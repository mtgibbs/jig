#!/usr/bin/env python3
"""Drive scripts/mcp-harness/server.py over stdio against a stub dispatcher.

Real HTTP on 127.0.0.1:0 so the server's own urllib path is exercised, but the socket is
bound BEFORE the server is spawned, so there is no readiness race to poll and nothing to
hang on. Every read is bounded; the whole run is bounded by the caller's timeout.

Emits one JSON object on stdout. Every field is always present; null means "not observed".
"""
import json, os, subprocess, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

SRV, OUT_TOKEN = sys.argv[1], sys.argv[2]
CALLS = []

class Stub(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _record(self):
        CALLS.append({"method": self.command, "path": self.path,
                      "auth": self.headers.get("Authorization", "")})

    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        self._record()
        p = self.path
        if p == "/runs":
            self._send(200, {"runs": [{"event_id": "known", "spec": "s", "status": "running"}]})
        elif p == "/runs/known":
            self._send(200, {"event_id": "known", "spec": "s", "status": "running"})
        elif p == "/runs/missing":
            self._send(404, {"error": "Run not found"})
        elif p == "/runs/unauth":
            self._send(401, {"error": "Unauthorized"})
        elif p == "/runs/known/evidence":
            self._send(501, {"error": "evidence retrieval is not implemented"})
        else:
            self._send(404, {"error": "Not found"})

    def do_POST(self):
        self._record()
        n = int(self.headers.get("Content-Length", 0) or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            body = {}
        CALLS[-1]["body"] = body
        if body.get("idempotency_key") == "replay":
            self._send(200, {"launched": False, "event_id": "replay", "note": "already seen"})
        elif not all(body.get(k) for k in ("repo", "spec", "strategy", "idempotency_key")):
            self._send(400, {"error": "missing field: strategy"})
        else:
            self._send(201, {"launched": True, "event_id": body["idempotency_key"]})

    def do_DELETE(self): self._record(); self._send(200, {})
    def do_PUT(self):    self._record(); self._send(200, {})

httpd = HTTPServer(("127.0.0.1", 0), Stub)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()

env = dict(os.environ)
env["HARNESS_API_URL"] = f"http://127.0.0.1:{port}"
env["HARNESS_API_TOKEN"] = OUT_TOKEN
env["PYTHONDONTWRITEBYTECODE"] = "1"

proc = subprocess.Popen([sys.executable, SRV], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, env=env, text=True, bufsize=1)

res = {"init": None, "tools": None, "launch_required": None, "launch_props": None,
       "results": {}, "calls": [], "bad_frame_survived": None, "stderr": ""}

def rpc(obj):
    """One request/response. Returns the parsed reply or None."""
    try:
        proc.stdin.write(json.dumps(obj) + "\n"); proc.stdin.flush()
        line = proc.stdout.readline()
        return json.loads(line) if line.strip() else None
    except Exception:
        return None

def call(name, args):
    r = rpc({"jsonrpc": "2.0", "id": name, "method": "tools/call",
             "params": {"name": name, "arguments": args}})
    # Flatten whatever shape the result takes into searchable text.
    return json.dumps(r) if r is not None else ""

try:
    r = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
    res["init"] = json.dumps(r) if r else None

    r = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    if r:
        blob = json.dumps(r)
        try:
            tools = r.get("result", {}).get("tools", [])
            res["tools"] = sorted(t.get("name", "") for t in tools)
            for t in tools:
                if t.get("name") == "launch_run":
                    sch = t.get("inputSchema") or t.get("input_schema") or {}
                    res["launch_required"] = sorted(sch.get("required", []) or [])
                    res["launch_props"] = json.dumps(sch.get("properties", {}) or {})
        except Exception:
            res["tools"] = None
        if res["tools"] is None:
            res["tools_raw"] = blob[:400]

    # A malformed frame must not kill the session: send garbage, then prove it still answers.
    try:
        proc.stdin.write("{not json\n"); proc.stdin.flush(); proc.stdout.readline()
    except Exception:
        pass
    r = rpc({"jsonrpc": "2.0", "id": 3, "method": "initialize", "params": {}})
    res["bad_frame_survived"] = bool(r)

    base = len(CALLS)
    res["results"]["list_runs"]   = call("list_runs", {})
    res["results"]["status_ok"]   = call("run_status", {"run_id": "known"})
    res["results"]["status_404"]  = call("run_status", {"run_id": "missing"})
    res["results"]["status_401"]  = call("run_status", {"run_id": "unauth"})
    res["read_calls"] = [f'{c["method"]} {c["path"]}' for c in CALLS[base:]]
    res["read_auth_ok"] = all(c["auth"].startswith("Bearer ") for c in CALLS[base:]) if CALLS[base:] else None

    res["results"]["evidence"]    = call("fetch_evidence", {"run_id": "known"})
    res["results"]["launch_ok"]   = call("launch_run", {"repo": "r", "spec": "s",
                                                        "strategy": "build-converge",
                                                        "idempotency_key": "fresh"})
    res["results"]["launch_replay"] = call("launch_run", {"repo": "r", "spec": "s",
                                                          "strategy": "build-converge",
                                                          "idempotency_key": "replay"})
    res["results"]["launch_400"]  = call("launch_run", {"repo": "r", "spec": "",
                                                        "strategy": "", "idempotency_key": "k"})
finally:
    res["calls"] = [f'{c["method"]} {c["path"]}' for c in CALLS]
    res["post_bodies"] = [c.get("body") for c in CALLS if c["method"] == "POST"]
    try:
        proc.stdin.close()
    except Exception:
        pass
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    try:
        res["stderr"] = (proc.stderr.read() or "")[-600:]
    except Exception:
        pass
    httpd.shutdown()

print(json.dumps(res))
