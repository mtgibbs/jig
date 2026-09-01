#!/usr/bin/env bash
# Gate for T01-selftest-artifact (20260831s-live-board-evidence).
#
# The loop ships its first-green selftest verdicts over the artifact channel it already uses
# for prompts and patches. Proven against the REAL ralph-build.sh on git fixtures carrying
# real mutant corpora, with a real HTTP sink on an ephemeral port recording what arrived.
#
# Why a live sink and not a grep of ralph-log.sh: the words "selftest" and "artifacts" are
# already all over this repo's prose (Trap A). What is being asserted is that a request with
# a body reaches a socket, which only a socket can tell us.
#
# ac2 is an ABSENCE assertion ("unset URL pushes nothing"), so it ships its positive control:
# the SAME fixture with the URL set must produce a request. Without that, a sink that never
# worked and a loop that correctly pushed nothing are the same observation (Trap B).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
# shellcheck source=/dev/null
. "$R/specs/lib/assert.sh"

NS="$R/scripts/new-spec.sh"
RB="$R/scripts/ralph-build.sh"

_TMP=""
_SINK_PID=""
cleanup() {
  [ -n "$_SINK_PID" ] && kill "$_SINK_PID" 2>/dev/null
  for d in $_TMP; do rm -rf "$d"; done
}
trap cleanup EXIT

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; _TMP="$_TMP $W"

# ── the sink ────────────────────────────────────────────────────────────────────────────────
# Records one "== <path> <bytes>" header per request followed by the verbatim body. Binds
# port 0 and prints the real port, so two gates running at once never collide.
cat > "$W/sink.py" <<'SINK'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
LOG = sys.argv[1]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n) if n else b""
        with open(LOG, "ab") as f:
            f.write(("== %s %d\n" % (self.path, len(body))).encode())
            f.write(body)
            if body and not body.endswith(b"\n"):
                f.write(b"\n")
        self.send_response(200); self.send_header("Content-Length", "0"); self.end_headers()
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers()
        self.wfile.write(b"{}")
srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_port, flush=True)
srv.serve_forever()
SINK

SINK_LOG="$W/sink.log"
: > "$SINK_LOG"
python3 "$W/sink.py" "$SINK_LOG" > "$W/port" 2>"$W/sink.err" &
_SINK_PID=$!
_n=0
while [ ! -s "$W/port" ] && [ "$_n" -lt 50 ]; do _n=$((_n+1)); sleep 0.1; done
PORT="$(head -1 "$W/port" 2>/dev/null || true)"
case "$PORT" in
  ''|*[!0-9]*) echo "  FAIL  gate: sink did not start (see $W/sink.err)" >&2; exit 2 ;;
esac
SINK_URL="http://127.0.0.1:$PORT"

# ── the fixture ─────────────────────────────────────────────────────────────────────────────
# A one-task spec whose gate wants greeting.txt to say hello. The corpus holds ONE mutant
# replacing greeting.txt with <mutant-body>; a body the gate rejects is killed, one it accepts
# survives. greeting.txt is 20 lines so a mutant's diff is long enough to be clipped.
mk_fx() {
  local d td
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _TMP="$_TMP $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs"
  bash "$NS" --root "$d" --id 20990101a fx greet >/dev/null 2>&1 || return 1
  td="$(ls -d "$d"/specs/20990101a-fx/tasks/T01-* 2>/dev/null | head -1)" || return 1
  cat > "$td/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q hello greeting.txt 2>/dev/null; then echo "  PASS  fx1"; exit 0; fi
echo "  FAIL  fx1: greeting.txt must say hello" >&2; exit 1
GATE
  chmod +x "$td/verify.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/20990101a-fx/verify.sh"
  chmod +x "$d/specs/20990101a-fx/verify.sh"
  rm -rf "$td/mutants"; mkdir -p "$td/mutants"
  {
    printf '# MUTANT: fx1\n# TARGET: greeting.txt\n'
    printf '# WHY: the plausible wrong greeting a lazy reading of fx1 would accept\n'
    _i=1
    while [ "$_i" -le 20 ]; do printf '%s line %d\n' "$1" "$_i"; _i=$((_i+1)); done
  } > "$td/mutants/greeting.txt"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null 2>&1
  printf '%s' "$d"
}

# The executor stand-in: writes the 20-line deliverable and a transcript long enough not to
# read as stillborn.
STUB="$W/exec.sh"
cat > "$STUB" <<'EXEC'
#!/usr/bin/env bash
: "${ROOT:?}"
i=1; : > "$ROOT/greeting.txt"
while [ "$i" -le 20 ]; do printf 'hello line %d\n' "$i" >> "$ROOT/greeting.txt"; i=$((i+1)); done
printf 'stub transcript line %d\n' $(seq 1 40)
exit 0
EXEC
chmod +x "$STUB"

# run_loop <root> <spec-rel> <report-url-or-empty> — SELFTEST_EVID is left to the loop's own
# default ($ROOT/.evidence), which is the path under test.
run_loop() {
  local root="$1" spec="$2" url="${3:-}"
  if [ -n "$url" ]; then
    ( cd "$root" && env -u SELFTEST_EVID HARNESS_REPORT_URL="$url" \
        RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
        SELFTEST_ARTIFACT_DIFF_LINES="${DIFF_LINES:-40}" \
        RALPH_EXEC_CMD="bash $STUB" bash "$RB" "$spec" 2>&1 )
  else
    ( cd "$root" && env -u SELFTEST_EVID -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN \
        RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
        RALPH_EXEC_CMD="bash $STUB" bash "$RB" "$spec" 2>&1 )
  fi
}

# sink_body <marker> — the body of the first recorded request whose path contains <marker>.
sink_body() {
  awk -v want="$1" '
    /^== / { keep = (index($2, want) > 0); next }
    keep   { print }
  ' "$SINK_LOG"
}

# ── ac1 + ac3 + ac4(KILLED) : a killed corpus pushes its verdicts ───────────────────────────
FX1="$(mk_fx goodbye)" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1" specs/20990101a-fx "$SINK_URL")"; rc1=$?

[ "$rc1" -eq 0 ] \
  && ok "ac1: the fixture run converged (rc=0) — the push did not disturb it" \
  || no "ac1: fixture run exited $rc1, expected 0 — the selftest or the push broke the loop"

grep -q '^== /runs/.*/artifacts/selftest ' "$SINK_LOG" \
  && ok "ac1: a request reached the coordinator at .../artifacts/selftest" \
  || no "ac1: no POST to .../artifacts/selftest arrived — the loop never pushed its selftest verdicts"

BODY1="$(sink_body /artifacts/selftest)"

printf '%s' "$BODY1" | grep -q '"verdict"[[:space:]]*:[[:space:]]*"KILLED"' \
  && ok "ac3: the pushed record carries the mutant's verdict" \
  || no "ac3: no KILLED verdict in the pushed record — the rows were not selected or not sent"

_miss=""
for _f in mutant assertion target why; do
  printf '%s' "$BODY1" | grep -q "\"$_f\"[[:space:]]*:" || _miss="$_miss $_f"
done
[ -z "$_miss" ] \
  && ok "ac3: every identifying field survives compaction (mutant, assertion, target, why)" \
  || no "ac3: compaction dropped$_miss — a row that cannot name its assertion cannot be read"

printf '%s' "$BODY1" | grep -q '"run_complete"' \
  && ok "ac3: the run_complete summary line is included" \
  || no "ac3: no run_complete line — the panel has no counts to render"

# Only this run's rows. The evidence file is append-only across runs and tasks, so a push that
# sends the FILE rather than the run's rows is the easy wrong implementation.
_n_ids="$(printf '%s' "$BODY1" | grep -o '"run_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | sed 's/.*"\([^"]*\)"$/\1/' | sort -u | wc -l | tr -d ' ')"
[ "${_n_ids:-0}" -eq 1 ] \
  && ok "ac3: the record holds exactly one run_id — this run's rows, not the whole file" \
  || no "ac3: the record spans ${_n_ids:-0} run_ids — the push sent the append-only file, not this run"

# "No diff on a KILLED row" is an ABSENCE assertion, and an empty body satisfies it for the
# wrong reason — which is exactly what the red run showed: it PASSED while nothing had been
# pushed at all (Trap B, found by running this gate before the build). Gate it on the body
# existing, so the absence is measured against something rather than against nothing.
if [ -n "$BODY1" ]; then
  printf '%s' "$BODY1" | grep -q '"diff"' \
    && no "ac4: a KILLED row shipped its diff — it is reconstructible from the committed corpus and is the only large field" \
    || ok "ac4: no diff on a KILLED row"
else
  no "ac4: nothing was pushed, so 'no diff on a KILLED row' measures nothing"
fi

# ── ac4(clipping) : a SURVIVOR ships its diff, clipped ──────────────────────────────────────
# A surviving mutant STOPs the run (exit 6, 20260831u). The push must already have happened:
# the run that refuses is exactly the run whose evidence must have left the worker.
: > "$SINK_LOG"
# "hello mutant", not "hello": the mutant must still satisfy the fixture gate (it contains
# hello, so it survives) while DIFFERING from what the executor writes. A survivor whose body
# is byte-identical to the deliverable produces a two-line header and no diff body at all —
# there is nothing to clip, and the clip assertion measures nothing.
FX2="$(mk_fx 'hello mutant')" || no "ac4: survivor fixture scaffold failed"
DIFF_LINES=3 run_loop "$FX2" specs/20990101a-fx "$SINK_URL" >/dev/null 2>&1
BODY2="$(sink_body /artifacts/selftest)"

printf '%s' "$BODY2" | grep -q '"verdict"[[:space:]]*:[[:space:]]*"SURVIVOR"' \
  && ok "ac4: the survivor's row left the worker even though the run refused" \
  || no "ac4: the survivor's row never arrived — the STOP path pushes nothing, which loses the one row that mattered"

printf '%s' "$BODY2" | grep -q '"diff"' \
  && ok "ac4: a non-KILLED row carries its install-time diff" \
  || no "ac4: the survivor shipped no diff — how the mutant was formed is exactly what a reader needs here"

printf '%s' "$BODY2" | grep -q 'diff clipped at 3 lines' \
  && ok "ac4: the diff is clipped to SELFTEST_ARTIFACT_DIFF_LINES and says so" \
  || no "ac4: no clip marker at the configured budget — an unbounded diff is what the byte cap truncates into invalid JSON"

# ── ac2 : unset URL pushes nothing, says nothing ────────────────────────────────────────────
# Positive control first: ac1 above already proved this sink records a real push from this
# exact fixture shape. Without that, "nothing recorded" would also be what a broken sink says.
: > "$SINK_LOG"
FX3="$(mk_fx goodbye)" || no "ac2: fixture scaffold failed"
out3="$(run_loop "$FX3" specs/20990101a-fx)"; rc3=$?

[ ! -s "$SINK_LOG" ] \
  && ok "ac2: an unset HARNESS_REPORT_URL pushed nothing (control: ac1 proved this sink records)" \
  || no "ac2: something was pushed with HARNESS_REPORT_URL unset — the unconfigured channel is not a degraded mode"

printf '%s' "$out3" | grep -Eqi 'push|coordinator|report url' \
  && no "ac2: the unconfigured run printed about pushing — it must be line-for-line the run it is today" \
  || ok "ac2: the unconfigured run said nothing about pushing"

[ "$rc3" -eq 0 ] \
  && ok "ac2: the unconfigured run still converged" \
  || no "ac2: the unconfigured run exited $rc3 — the push path changed a run that does not use it"

# ── ac5 : an unreachable coordinator never fails the run ────────────────────────────────────
# Port 1 is reserved and refuses instantly; a refused connection is the fast half of this
# contract and the one a laptop actually hits.
FX4="$(mk_fx goodbye)" || no "ac5: fixture scaffold failed"
_t0=$(date +%s)
out4="$(run_loop "$FX4" specs/20990101a-fx http://127.0.0.1:1)"; rc4=$?
_t1=$(date +%s)

[ "$rc4" -eq 0 ] \
  && ok "ac5: an unreachable coordinator left the run's exit code alone (rc=0)" \
  || no "ac5: the run exited $rc4 against a dead coordinator — the push is fire-and-forget by contract"

[ $((_t1 - _t0)) -lt 120 ] \
  && ok "ac5: the run did not hang waiting on the dead coordinator ($((_t1 - _t0))s)" \
  || no "ac5: the run took $((_t1 - _t0))s against a dead coordinator — the push must be timeout-bounded"

gate_done
