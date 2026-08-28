#!/usr/bin/env python3
"""Stub coordinator. Records every request; answers /control from a file the gate controls.

Verifying against a stub rather than the real API is deliberate and stronger: it pins the contract
without waiting on the other half to exist, and it lets the gate script an intent arriving
mid-run, which is the case that matters and the one a live server makes hard to stage.
"""
import json, os, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT, ACTION = sys.argv[1], sys.argv[2]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _rec(self, body=""):
        with open(OUT, "a") as f:
            f.write(json.dumps({"m": self.command, "p": self.path,
                                "auth": self.headers.get("Authorization", ""),
                                "b": body[:2000]}) + "\n")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        self._rec(self.rfile.read(n).decode("utf-8", "replace"))
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers()
        self.wfile.write(b"{}")
    def do_GET(self):
        self._rec()
        act = "none"
        try: act = open(ACTION).read().strip() or "none"
        except Exception: pass
        if act == "BROKEN":                       # a body that cannot be read is NOT a cancel
            body = b"<<<not json>>>"
        elif act == "500":
            self.send_response(500); self.send_header("Content-Length", "0"); self.end_headers(); return
        else:
            body = json.dumps({"action": act}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
threading.Thread(target=srv.serve_forever, daemon=True).start()
try:
    while True: threading.Event().wait(3600)
except KeyboardInterrupt: pass
