# fixtures.sh — the four endpoints a probe has to tell apart, and the configs that name them.
#
# Sourced by the gates, never executed. Requires $T from gate_tmpdir.
#
# The whole point of this spec is that these four produce four DIFFERENT answers. A probe that
# reports "unreachable" for all of them passes any test that only checks "did it fail" — and that
# undifferentiated answer is the 2026-08-28 bug itself, not a lesser version of it.

# fixture_start <mode> — mode is ok | unauthorized | html404
# Sets FIX_URL and FIX_PIDFILE. The server answers on 127.0.0.1 on an OS-assigned port.
fixture_start() {
  local mode="$1"
  local portfile="$T/fix.$mode.port"
  rm -f "$portfile"
  python3 - "$mode" "$portfile" <<'PYX' &
import http.server, json, socketserver, sys, threading

mode, portfile = sys.argv[1], sys.argv[2]

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def _send(self, code, body, ctype="application/json"):
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(n)
        # An MCP client that gets a 401 falls back to OAuth dynamic client registration and
        # POSTs /register. A server that never implemented OAuth answers with an HTML 404 —
        # which is what the operator sees, and what must NOT read as "the server is down".
        if self.path.endswith("/register"):
            return self._send(404, "<!DOCTYPE html><html><body><pre>Cannot POST /register</pre></body></html>", "text/html")
        if mode == "unauthorized":
            return self._send(401, json.dumps({"error": "unauthorized"}))
        if mode == "html404":
            return self._send(404, "<!DOCTYPE html><html><body><pre>Cannot POST /mcp</pre></body></html>", "text/html")
        return self._send(200, json.dumps({
            "jsonrpc": "2.0", "id": 1,
            "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}},
                       "serverInfo": {"name": "fixture-mcp", "version": "0.0.1"}}}))

    do_GET = do_POST

srv = socketserver.TCPServer(("127.0.0.1", 0), H)
open(portfile, "w").write(str(srv.server_address[1]))
threading.Thread(target=srv.serve_forever, daemon=True).start()
threading.Event().wait(3600)
PYX
  FIX_PID=$!
  local i=0
  while [ ! -s "$portfile" ] && [ $i -lt 60 ]; do sleep 0.1; i=$((i+1)); done
  FIX_URL="http://127.0.0.1:$(cat "$portfile" 2>/dev/null)/mcp"
}

fixture_stop() { kill "$FIX_PID" 2>/dev/null; wait "$FIX_PID" 2>/dev/null; }

# A port nothing is listening on. Connection refused, instantly — the cheap half of `unreachable`.
DEAD_URL="http://127.0.0.1:1/mcp"

# mkconfig <path> <server-name> <url> <env-var-name> [interp]
# Writes an executor config in the binding's shape. `interp` selects the interpolation spelling:
# opencode's {env:NAME} (default) or the ${NAME} form .mcp.json uses. Both are in live use in this
# homelab, so a probe that understands only one of them is a probe that reports `unconfigured`
# against a perfectly good config.
mkconfig() {
  local path="$1" name="$2" url="$3" var="$4" interp="${5:-env}"
  local ref="{env:$var}"
  [ "$interp" = "dollar" ] && ref="\${$var}"
  mkdir -p "$(dirname "$path")"
  python3 - "$path" "$name" "$url" "$ref" <<'PYX'
import json, sys
path, name, url, ref = sys.argv[1:5]
json.dump({"mcp": {name: {"type": "remote", "url": url, "headers": {"X-API-Key": ref}}}},
          open(path, "w"), indent=2)
PYX
}

# gate_timeout <seconds> <cmd...> — bound a command, returning 124 when the bound elapses.
#
# `timeout(1)` is coreutils and is NOT on a stock macOS. Calling it there does not time out, it
# returns 127 — which reads as a failed assertion rather than a missing tool, so a gate that
# assumes it silently reports nonsense on the laptop it was supposed to be runnable on. Prefer the
# real thing, then Homebrew's `gtimeout`, then a portable watchdog.
gate_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@" &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -ge "$((secs * 10))" ] && { kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; }
    sleep 0.1; i=$((i+1))
  done
  wait "$pid"; return $?
}

# probe <args...> — run the probe under test, capturing stdout+stderr and its exit code.
# Sets PROBE_OUT and PROBE_RC. Bounded, so a missing timeout inside the probe shows up here as
# rc 124 rather than as a gate that never returns.
probe() {
  PROBE_OUT="$( (cd "$T" && gate_timeout 30 bash "$ROOT/scripts/mcp-probe.sh" "$@") 2>&1 )"
  PROBE_RC=$?
}
