#!/usr/bin/env python3
"""coordinator.py — receives what workers push, serves what a human watches.

The receiving half of the worker channel. Workers POST their status, their attempt records and
their artifacts; this holds them and serves a live board. It never dials a worker: nothing can
connect into one, so control flows the other way too — an intent is parked here and the worker
collects it on its next poll, exactly as a CI runner discovers cancellation.

Deliberately separate from api.py. That one creates compute and is cluster-internal with no
ingress (ADR-001 D9); this one is read-mostly and is the thing a browser opens. Merging them
would put a route a human loads on the same surface as a route that launches Jobs.

State is in memory with an optional JSON snapshot. Artifacts are capped and pruned — a
coordinator that keeps everything is a log server nobody configured.
"""
import json, os, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_ARTIFACT = int(os.environ.get("COORD_MAX_ARTIFACT_BYTES", 1 << 20))
MAX_RUNS = int(os.environ.get("COORD_MAX_RUNS", 200))
STATE_PATH = os.environ.get("COORD_STATE_PATH", "")
TOKEN = os.environ.get("HARNESS_REPORT_TOKEN", "")

_lock = threading.Lock()
# run_key -> {"status": {...}, "attempts": [...], "artifacts": {"T1/1/prompt": bytes},
#             "control": "none", "first_seen": ts, "last_seen": ts}
RUNS = {}


def _now():
    return int(time.time())


def _touch(key):
    r = RUNS.get(key)
    if r is None:
        r = {"status": {}, "attempts": [], "artifacts": {}, "control": "none",
             "first_seen": _now(), "last_seen": _now()}
        RUNS[key] = r
        # Oldest-first eviction. Without a bound this grows for the life of the process, and the
        # thing that falls over is the dashboard rather than anything that would page someone.
        if len(RUNS) > MAX_RUNS:
            for k in sorted(RUNS, key=lambda k: RUNS[k]["last_seen"])[:len(RUNS) - MAX_RUNS]:
                RUNS.pop(k, None)
    r["last_seen"] = _now()
    return r


def _save():
    if not STATE_PATH:
        return
    try:
        snap = {k: {"status": v["status"], "attempts": v["attempts"][-50:],
                    "control": v["control"], "first_seen": v["first_seen"],
                    "last_seen": v["last_seen"],
                    # artifact BYTES are deliberately not snapshotted: they are the bulk, they are
                    # reproducible from the worker, and writing them here turns a restart-safety
                    # feature into a disk-filling one.
                    "artifact_keys": sorted(v["artifacts"])}
                for k, v in RUNS.items()}
        tmp = STATE_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(snap, f)
        os.replace(tmp, STATE_PATH)
    except Exception:
        pass


def _load():
    if not STATE_PATH or not os.path.exists(STATE_PATH):
        return
    try:
        with open(STATE_PATH) as f:
            snap = json.load(f)
        for k, v in snap.items():
            RUNS[k] = {"status": v.get("status", {}), "attempts": v.get("attempts", []),
                       "artifacts": {}, "control": v.get("control", "none"),
                       "first_seen": v.get("first_seen", 0), "last_seen": v.get("last_seen", 0)}
    except Exception:
        pass


def _authed(handler):
    if not TOKEN:
        return True
    got = handler.headers.get("Authorization", "")
    return got == "Bearer " + TOKEN


class H(BaseHTTPRequestHandler):
    server_version = "harness-coordinator/1"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, body):
        raw = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    # --- POST: everything the worker pushes ---------------------------------------------------
    def do_POST(self):
        # Where the boundary sits, and why it is not in the obvious place.
        #
        # WRITES OF RUN DATA need the token: status, attempts and artifacts are the record, and
        # anyone who can forge them can make the board lie about what happened. That is the
        # integrity boundary worth defending.
        #
        # CONTROL is deliberately outside it. The board is a page a browser opens, and a browser
        # cannot send an Authorization header from a plain link — requiring one here would mean
        # the Stop button could never work from the thing built to house it. The worst a control
        # write can do is stop or pause a build that can be started again, on a host reachable
        # only through Pi-hole's split-horizon DNS. That trade is worth stating rather than
        # discovering: it is a real relaxation, taken knowingly, on a LAN-only surface.
        parts_pre = [p for p in self.path.split("?")[0].split("/") if p]
        is_control = len(parts_pre) == 4 and parts_pre[0] == "runs" and parts_pre[3] == "control"
        if not is_control and not _authed(self):
            return self._json(401, {"error": "unauthorized"})
        n = int(self.headers.get("Content-Length", 0) or 0)
        if n > MAX_ARTIFACT:
            # Read and discard so the connection closes cleanly; the worker must never block.
            self.rfile.read(min(n, MAX_ARTIFACT))
            return self._json(413, {"error": "too large", "max": MAX_ARTIFACT})
        raw = self.rfile.read(n) if n else b""
        parts = [p for p in self.path.split("?")[0].split("/") if p]
        # /runs/<host>/<agent-pid>/...
        if len(parts) < 4 or parts[0] != "runs":
            return self._json(404, {"error": "no such route"})
        key = parts[1] + "/" + parts[2]
        rest = parts[3:]
        # Route validation FIRST, _touch second (issue #46). _touch creates the row AND runs
        # oldest-first eviction, so a POST that is about to 404 could both put a ghost row on
        # the board and evict a real run's record to make room for it. A route that 404s must
        # not be able to change what the board says.
        known = (rest in (["status"], ["attempts"], ["control"])
                 or (len(rest) == 5 and rest[0] == "attempts" and rest[3] == "artifacts"))
        if not known:
            return self._json(404, {"error": "no such route", "path": self.path})
        with _lock:
            r = _touch(key)
            if rest == ["status"]:
                try:
                    r["status"] = json.loads(raw.decode("utf-8", "replace"))
                except Exception:
                    return self._json(400, {"error": "status body is not JSON"})
            elif rest == ["attempts"]:
                try:
                    r["attempts"].append(json.loads(raw.decode("utf-8", "replace")))
                except Exception:
                    return self._json(400, {"error": "attempt body is not JSON"})
            elif len(rest) == 5 and rest[0] == "attempts" and rest[3] == "artifacts":
                r["artifacts"]["%s/%s/%s" % (rest[1], rest[2], rest[4])] = raw
            elif rest == ["control"]:
                try:
                    r["control"] = json.loads(raw.decode("utf-8", "replace")).get("action", "none")
                except Exception:
                    return self._json(400, {"error": "control body is not JSON"})
            else:
                return self._json(404, {"error": "no such route", "path": self.path})
            _save()
        return self._json(200, {"ok": True})

    # --- GET: what the worker polls, and what a human opens ------------------------------------
    def do_GET(self):
        path = self.path.split("?")[0]
        parts = [p for p in path.split("/") if p]

        # The worker's control poll. Answered even without a token so a misconfigured worker
        # degrades to "no intent" rather than to an error it would have to interpret.
        if len(parts) == 4 and parts[0] == "runs" and parts[3] == "control":
            with _lock:
                r = RUNS.get(parts[1] + "/" + parts[2])
                return self._json(200, {"action": (r or {}).get("control", "none")})

        # Reads are open on the LAN. The board is served to a browser, which cannot present a
        # bearer token, and this host answers only to names Pi-hole resolves. What it exposes is
        # run metadata and evidence — not credentials, which never enter this service at all.
        if path == "/api/runs":
            with _lock:
                return self._json(200, {"runs": _summary()})
        if len(parts) == 4 and parts[0] == "artifact":
            with _lock:
                r = RUNS.get(parts[1])
            return self._json(404, {"error": "use /api/artifact"})
        if path == "/api/artifact":
            return self._json(400, {"error": "key required"})
        if path in ("/", "/index.html"):
            return self._html(_page())
        return self._json(404, {"error": "no such route"})


def _summary():
    out = []
    for key, r in RUNS.items():
        st = r["status"] or {}
        out.append({
            "key": key,
            "spec": (st.get("spec") or "").split("/")[-1],
            "branch": st.get("branch", ""),
            "agent": st.get("agent", ""),
            "task_index": st.get("task_index", 0),
            "total_tasks": st.get("total_tasks", 0),
            "attempt": st.get("attempt", 0),
            "max_attempts": st.get("max_attempts", 0),
            "phase": st.get("phase", "?"),
            "task": (st.get("task") or "")[:160],
            "started": st.get("started", r["first_seen"]),
            "updated": st.get("updated", r["last_seen"]),
            "control": r["control"],
            "attempts": r["attempts"][-25:],
            "artifacts": sorted(r["artifacts"]),
        })
    out.sort(key=lambda x: x["updated"], reverse=True)
    return out


def _page():
    here = os.path.dirname(os.path.abspath(__file__))
    tpl = os.path.join(here, "board.html")
    try:
        with open(tpl, encoding="utf-8") as f:
            return f.read()
    except Exception:
        return "<title>Jig</title><p>board.html missing next to coordinator.py</p>"


def serve(port=None):
    _load()
    port = int(port if port is not None else os.environ.get("COORD_PORT", 8877))
    srv = ThreadingHTTPServer(("0.0.0.0", port), H)
    sys.stderr.write("coordinator listening on %d (token %s)\n"
                     % (port, "required" if TOKEN else "NOT SET — open"))
    sys.stderr.flush()
    srv.serve_forever()


if __name__ == "__main__":
    serve(sys.argv[1] if len(sys.argv) > 1 else None)
