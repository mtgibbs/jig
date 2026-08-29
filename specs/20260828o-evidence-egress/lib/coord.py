#!/usr/bin/env python3
"""Stub coordinator for the evidence channel.

Differs from the worker-channel stub in one way that matters: it records each body's FULL byte
count and saves the bytes to a file, rather than keeping a truncated copy inline. This spec's
assertions are about size and about a marker surviving truncation, and a stub that clips bodies
at 2000 characters cannot tell a capped artifact from an uncapped one — it would report every
artifact as truncated and pass an implementation that never truncated anything.
"""
import json, os, sys, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = sys.argv[1]
BODIES = OUT + ".d"
os.makedirs(BODIES, exist_ok=True)
SEQ = [0]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n)
        SEQ[0] += 1
        path = os.path.join(BODIES, "%04d.body" % SEQ[0])
        with open(path, "wb") as f:
            f.write(raw)
        with open(OUT, "a") as f:
            f.write(json.dumps({"m": self.command, "p": self.path,
                                "auth": self.headers.get("Authorization", ""),
                                "n": len(raw), "f": path}) + "\n")
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers()
        self.wfile.write(b"{}")
    def do_GET(self):
        body = b'{"action":"none"}'
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
threading.Thread(target=srv.serve_forever, daemon=True).start()
try:
    while True: threading.Event().wait(3600)
except KeyboardInterrupt: pass
