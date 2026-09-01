# MUTANT: ac16
# TARGET: scripts/jig-board.sh
# WHY: starts the board and prints the URL without recording the pid, on the reasoning that
# WHY: the port probe already tells you whether one is running. It does — and stop then has
# WHY: nothing to stop, so the board outlives every attempt to shut it down.
#!/usr/bin/env bash
# jig-board.sh — the Jig board, as a local service.
#
#   scripts/jig-board.sh start    # bring it up, print the URL
#   scripts/jig-board.sh status   # running or not, and where
#   scripts/jig-board.sh stop     # bring it down
#   scripts/jig-board.sh url      # just the URL, for scripting
#
# docs/coordinator.md already said the coordinator runs anywhere and needs nothing. It does —
# but "runs anywhere" meant holding two things in your head at once: start coordinator.py, and
# then remember to export HARNESS_REPORT_URL at the value it happens to be listening on. The
# docker-compose laptop mode removes that and adds Docker, which the dependency list — a clone,
# a shell, and a model endpoint — does not have. This is the third option: python3 and nothing.
#
# It INVENTS NO PORT. COORD_PORT is the variable coordinator.py already reads, that
# docker/compose.yaml already publishes, and that the pi-cluster ingress already backends;
# a second name for the same number is a second thing to get wrong.
#
# State lives in .jig/ at the repo root, which is gitignored — the board's pid and its run
# snapshot belong to the checkout you are working in, not to the repo.
#
# bash 3.2 floor (macOS): no arrays, no declare -A, no ${var,,}.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORD="$SCRIPT_DIR/dispatch/coordinator.py"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_DIR="$ROOT/.jig"
PIDFILE="$STATE_DIR/board.pid"
LOGFILE="$STATE_DIR/board.log"
SNAPSHOT="$STATE_DIR/coord-state.json"

PORT="${COORD_PORT:-8877}"
URL="http://127.0.0.1:$PORT"

die() { echo "jig-board: $*" >&2; exit 1; }

# _pid — the recorded pid, but only if it names a live process. A stale pidfile is worse than
# no pidfile: it makes status lie and makes stop report success against nothing.
_pid() {
  local p
  [ -f "$PIDFILE" ] || return 1
  p="$(head -1 "$PIDFILE" 2>/dev/null || true)"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null || return 1
  printf '%s' "$p"
}

# _answering — something is serving the board API on PORT. Not necessarily OURS: a second
# worktree's board, or docker compose, is a perfectly good board and starting a second process
# on a held port produces one coordinator and one crash loop.
_answering() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null --connect-timeout 1 "$URL/api/runs" 2>/dev/null
  else
    python3 - "$URL/api/runs" <<'PY' 2>/dev/null
import sys, urllib.request
try:
    urllib.request.urlopen(sys.argv[1], timeout=1)
except Exception:
    sys.exit(1)
PY
  fi
}

cmd_start() {
  local pid n
  if pid="$(_pid)"; then
    echo "jig-board: already running on $URL (pid $pid)"
    return 0
  fi
  if _answering; then
    # Not ours, and that is fine — say so rather than silently adopting it, because `stop`
    # will not be able to end it and an operator should know why.
    echo "jig-board: a board is already serving $URL (not started here — stop it where it was started)"
    return 0
  fi
  [ -f "$COORD" ] || die "coordinator not found at $COORD"
  command -v python3 >/dev/null 2>&1 || die "python3 is required"
  mkdir -p "$STATE_DIR" || die "cannot create $STATE_DIR"

  COORD_PORT="$PORT" COORD_STATE_PATH="${COORD_STATE_PATH:-$SNAPSHOT}" \
    nohup python3 "$COORD" >> "$LOGFILE" 2>&1 &
  pid=$!

  n=0
  while [ "$n" -lt 80 ]; do
    _answering && break
    kill -0 "$pid" 2>/dev/null || break
    n=$((n+1)); sleep 0.1
  done
  if _answering; then
    echo "jig-board: listening on $URL (pid $pid, log $LOGFILE)"
    return 0
  fi
  # Fail LOUD, with the log path. Every push in this repo is fire-and-forget; this is the one
  # surface a human asked for directly, and silently not getting it is the wrong failure.
  rm -f "$PIDFILE"
  echo "jig-board: failed to start on $PORT — see $LOGFILE" >&2
  [ -s "$LOGFILE" ] && tail -5 "$LOGFILE" | sed 's/^/    | /' >&2
  return 1
}

cmd_stop() {
  local pid n
  if ! pid="$(_pid)"; then
    rm -f "$PIDFILE"
    echo "jig-board: not running"
    return 0
  fi
  kill "$pid" 2>/dev/null
  n=0
  while [ "$n" -lt 50 ] && kill -0 "$pid" 2>/dev/null; do n=$((n+1)); sleep 0.1; done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  rm -f "$PIDFILE"
  echo "jig-board: stopped (was pid $pid)"
  return 0
}

cmd_status() {
  local pid
  if pid="$(_pid)"; then
    echo "jig-board: running on $URL (pid $pid, log $LOGFILE)"
    return 0
  fi
  if _answering; then
    echo "jig-board: running on $URL (started elsewhere — no pidfile here)"
    return 0
  fi
  echo "jig-board: stopped — nothing listening on $URL"
  return 3
}

case "${1:-}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  url)    echo "$URL" ;;
  *)
    echo "usage: jig-board.sh <start|stop|status|url>   (port: COORD_PORT, default 8877)" >&2
    exit 1 ;;
esac
