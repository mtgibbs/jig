#!/usr/bin/env bash
# T2 — a failed launch says which failure it was.
#
# Behavioural, through the module's own API, with `runner=` pointed at stubs — the same shape as
# 20260830a T01 and 20260829a T05, because a second style for reading a dispatcher failure would
# be a second thing to learn.
#
# The distinction under test is not cosmetic. In a Deployment, launch()'s return value is the
# entire diagnostic surface: "kubectl is not on PATH" (the image is wrong) and "the API server
# rejected this Job" (the RBAC or the body is wrong) are different incidents with different fixes,
# and today they are the same integer with no text.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

D="$ROOT/scripts/dispatch/dispatcher.py"
[ -f "$D" ] || { no "ac0: scripts/dispatch/dispatcher.py is missing"; gate_done; }

# Three stubs standing in for the three outcomes kubectl can produce.
cat > "$T/ok.sh"  <<'S'
#!/usr/bin/env bash
cat >/dev/null; exit 0
S
cat > "$T/bad.sh" <<'S'
#!/usr/bin/env bash
cat >/dev/null
echo 'error validating data: BAD-JOB-SENTINEL' >&2
exit 1
S
chmod +x "$T/ok.sh" "$T/bad.sh"

# probe <runner> [env-runner] — call launch(), print RC/OUT/ERR on one line each.
probe() {
  ( cd "$ROOT/scripts/dispatch" && HARNESS_KUBECTL="${2:-}" T="$T" RUNNER="$1" python3 -c "
import sys, os, io, contextlib
sys.path.insert(0, '.')
import dispatcher as d
r = os.environ['RUNNER'] or None
if not os.environ.get('HARNESS_KUBECTL'): os.environ.pop('HARNESS_KUBECTL', None)
o, e = io.StringIO(), io.StringIO()
rc = 'RAISED'
try:
    with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
        rc = d.launch({'kind': 'Job', 'metadata': {'name': 'x'}}, runner=r)
except Exception as exc:
    rc = 'RAISED:' + type(exc).__name__
print('RC=' + str(rc))
print('OUT=' + o.getvalue().replace(chr(10), ' '))
print('ERR=' + e.getvalue().replace(chr(10), ' '))
" ) 2>/dev/null
}

# ── ac1: success stays silent and returns 0 ──────────────────────────────────────────────────
p="$(probe "$T/ok.sh")"
rc="$(echo "$p" | sed -n 's/^RC=//p')"; out="$(echo "$p" | sed -n 's/^OUT=//p')"; err="$(echo "$p" | sed -n 's/^ERR=//p')"
if [ "$rc" != "0" ]; then
  no "ac1: a successful apply returned $rc, not 0 — every caller reads this as failure"
elif [ -n "$out$err" ]; then
  no "ac1: the happy path emitted output (out=[$out] err=[$err]). A dispatcher that logs every success buries the one line that matters"
else
  ok "ac1: a successful apply returns 0 and says nothing"
fi

# ── ac2: a rejected apply surfaces the server's own words ────────────────────────────────────
p="$(probe "$T/bad.sh")"
rc="$(echo "$p" | sed -n 's/^RC=//p')"; out="$(echo "$p" | sed -n 's/^OUT=//p')"; err="$(echo "$p" | sed -n 's/^ERR=//p')"
if [ "$rc" = "0" ]; then
  no "ac2: a rejected apply returned 0 — the dispatcher would record a run that was never created"
elif ! echo "$err" | grep -q 'BAD-JOB-SENTINEL'; then
  no "ac2: the runner's stderr was captured and discarded (err=[$err]). It is captured into a PIPE today and dropped, which is why a rejected Job reaches a human as a bare exit code"
elif [ -n "$out" ]; then
  no "ac2: the diagnostic went to stdout (out=[$out]). stdout is where a caller may be reading structured output; diagnostics belong on stderr"
else
  ok "ac2: a rejected apply returns non-zero and surfaces the runner's stderr, on stderr"
fi
REJECTED_ERR="$err"

# ── ac3: a missing runner is a DIFFERENT message ─────────────────────────────────────────────
p="$(probe "$T/no-such-kubectl")"
rc="$(echo "$p" | sed -n 's/^RC=//p')"; err="$(echo "$p" | sed -n 's/^ERR=//p')"
case "$rc" in RAISED*)
  no "ac3: launch() raised on a missing runner ($rc). Its docstring promises it never raises, and dispatch() has no handler — a typo'd HARNESS_KUBECTL would take the process down" ;;
esac
if [ "$rc" = "0" ]; then
  no "ac3: a missing runner returned 0 — the dispatcher would believe it had launched a Job that does not exist"
elif [ -z "$err" ]; then
  no "ac3: a missing runner produced no message at all. This is the failure mode of a wrong image, and it is indistinguishable from a rejected Job without one"
elif ! echo "$err" | grep -q 'no-such-kubectl'; then
  no "ac3: the message does not name the runner it could not execute (err=[$err]) — naming it is what points at HARNESS_KUBECTL or the image rather than at the Job body"
elif [ "$err" = "$REJECTED_ERR" ]; then
  no "ac3: a missing runner and a rejected apply produce the SAME message. Two incidents with different fixes must not read identically"
else
  ok "ac3: a missing runner returns non-zero with its own message, naming the runner"
fi

# ── ac4: the signature and its precedence are unchanged ──────────────────────────────────────
# 20260828f and 20260829a T05 both assert through this signature; changing it changes their gates.
p="$(probe "$T/ok.sh" "$T/bad.sh")"
rc="$(echo "$p" | sed -n 's/^RC=//p')"
if [ "$rc" != "0" ]; then
  no "ac4: with runner= given AND HARNESS_KUBECTL set, the environment won (rc=$rc). The explicit argument must win — the env var is the fallback, and two other specs' gates rely on that order"
else
  ok "ac4: runner= takes precedence over HARNESS_KUBECTL, as before"
fi

# ── ac5: still never raises, including on a job it cannot serialise ──────────────────────────
# json.dumps() sits OUTSIDE the try today, so a non-serialisable job raises out of a function
# documented as never raising.
p="$( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys; sys.path.insert(0, '.')
import dispatcher as d
try:
    rc = d.launch({'kind': object()}, runner='/bin/true')
    print('RC=' + str(rc))
except Exception as exc:
    print('RC=RAISED:' + type(exc).__name__)
" 2>/dev/null )"
case "$p" in
  *RAISED*) no "ac5: launch() raised on an unserialisable Job ($p). The docstring says 'Never raises' and dispatch() has no handler, so this reaches the top of the process" ;;
  RC=0)     no "ac5: an unserialisable Job returned 0 — success is the one answer it cannot be" ;;
  RC=*)     ok "ac5: launch() still never raises, and reports failure instead" ;;
  *)        no "ac5: the probe produced nothing readable ($p)" ;;
esac

gate_done
