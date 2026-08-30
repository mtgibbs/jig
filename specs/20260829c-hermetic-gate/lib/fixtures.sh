# fixtures.sh — helpers for this spec's gates.
#
# NOTE the ordering trap this file lives inside. Sourcing assert.sh is what makes a gate
# hermetic, so a gate here must source assert.sh FIRST and only then set HARNESS_REPORT_URL for
# the case it is testing. A gate that sets it first would have it unset out from under itself and
# would measure the reset by accident rather than on purpose.

# stub_start — a recording server on localhost. Sets STUB_URL and STUB_LOG.
stub_start() {
  STUB_LOG="$T/stub.log"; : > "$STUB_LOG"
  rm -f "$T/stub.port"
  python3 "$ROOT/specs/20260829c-hermetic-gate/lib/stub.py" "$STUB_LOG" > "$T/stub.port" 2>"$T/stub.err" &
  STUB_PID=$!
  local i=0
  while [ ! -s "$T/stub.port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  STUB_URL="http://127.0.0.1:$(cat "$T/stub.port" 2>/dev/null)"
}

stub_stop() { [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2>/dev/null; wait "$STUB_PID" 2>/dev/null || true; }

# stub_hits — how many requests reached the stub. Exactly one integer, always.
#
# `grep -c || echo 0` is the obvious idiom and is WRONG: grep -c PRINTS 0 and EXITS 1 when it
# matches nothing, so the fallback fires too and the caller gets two lines. Every numeric test
# against that then errors, and a failing `[ ]` sends an if/elif chain to its else — which here
# is the PASS branch. Borrowed from 20260828o's fixtures, where it cost two false passes.
stub_hits() {
  local n
  n="$(wc -l < "${STUB_LOG:-/dev/null}" 2>/dev/null || printf 0)"
  printf '%s' "$n" | tr -dc '0-9'
}

# quarantined — the set, in one place, for the gates that check it.
QUARANTINED="HARNESS_REPORT_URL HARNESS_REPORT_TOKEN RALPH_FORCE_ALL RALPH_FORCE_FROM RALPH_SATISFIED_TIMEOUT"

# strip_comments <file> — instruction lines only.
#
# Every variable name in QUARANTINED appears in this spec's prose, in the write-up, and in the
# comments that explain why each is quarantined. A check that reads comments reports a finished
# migration as unfinished forever.
strip_comments() { sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$1" 2>/dev/null; }
