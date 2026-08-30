"""A coordinator that records what reached it and nothing else.

Exists so an ABSENCE can be proved. Every failure in this spec's §1 passed by observing nothing
and calling it clean; "the stub's log is empty" means that too, unless the same stub has been
shown to fill. So this records EVERY request, of any method and path, one line each, and the
gate posts to it directly as a positive control before trusting an empty log.
"""
import socketserver
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[1]
_lock = threading.Lock()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _record(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        with _lock:
            with open(LOG, "a") as f:
                f.write(f"{self.command} {self.path}\n")
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_POST = do_PUT = do_GET = _record


class Q(HTTPServer):
    """HTTPServer without the reverse-DNS lookup in server_bind.

    HTTPServer.server_bind calls socket.getfqdn() to fill server_name. On a machine whose
    resolver has no quick answer for the local address that call BLOCKS — measured here at
    longer than the gate's readiness wait, so the port line was never printed, the gate read
    an empty port, and it reported "the stub never came up". The server was fine and starting
    to listen; only the banner was stuck behind a DNS query nothing needs.

    Worth the subclass rather than a longer wait: a readiness timeout hides this as slowness
    instead of naming it, and a gate that is merely slow on one machine is a gate that gets
    dropped from the loop.
    """

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]


s = Q(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
