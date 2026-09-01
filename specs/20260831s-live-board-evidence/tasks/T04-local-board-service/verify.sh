#!/usr/bin/env bash
# Gate for T04-local-board-service (20260831s-live-board-evidence).
#
# Runs jig-board.sh for real on an ephemeral port and drives the REAL run-loop.sh inside a git
# fixture, because what is being asserted is that a process starts and that a variable reaches
# a phase — neither of which a grep can see.
#
# ac19 is an ABSENCE assertion ("no flag, no board, no export"), so it ships its positive
# control: the SAME fixture WITH --board must show the probe reading a non-empty
# HARNESS_REPORT_URL. Otherwise a probe that never fires and a run-loop that correctly
# exported nothing produce identical output (Trap B).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
# shellcheck source=/dev/null
. "$R/specs/lib/assert.sh"

JB="$R/scripts/jig-board.sh"
RL="$R/scripts/run-loop.sh"
DOC="$R/docs/coordinator.md"

_TMP=""
_STARTED=""
cleanup() {
  for p in $_STARTED; do kill "$p" 2>/dev/null; done
  for d in $_TMP; do rm -rf "$d"; done
}
trap cleanup EXIT

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; _TMP="$_TMP $W"

freeport() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

# ── the fixture: a repo, off main, with a stub strategy whose build phase is a probe ────────
mk_fx() {
  local d
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _TMP="$_TMP $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  git -C "$d" checkout -q -b fx 2>/dev/null || git -C "$d" checkout -q -B fx
  mkdir -p "$d/.harness/loops" "$d/specs/fx"

  # The probe stands in for the build phase and records what the phase actually saw.
  cat > "$d/probe.sh" <<'PROBE'
#!/usr/bin/env bash
printf 'REPORT_URL=[%s]\n' "${HARNESS_REPORT_URL:-}" > "$FX_PROBE_OUT"
exit 0
PROBE
  chmod +x "$d/probe.sh"

  cat > "$d/.harness/loops/fx.conf" <<CONF
STRATEGY_DESC="fixture"
STRATEGY_PHASES="build"
BUILD_CMD="$d/probe.sh"
CONF

  printf '# Spec: fx\n\n- **Tools:** bash\n- **MCP:** none\n' > "$d/specs/fx/spec.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"
  chmod +x "$d/specs/fx/verify.sh"
  printf 'T1: fixture task\n' > "$d/specs/fx/tasks.txt"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" commit -qm fx >/dev/null 2>&1
  printf '%s' "$d"
}

[ -f "$JB" ] || no "gate: scripts/jig-board.sh does not exist"
[ -x "$JB" ] || no "gate: scripts/jig-board.sh is not executable"

if [ -f "$JB" ]; then
  # ── ac16 : start brings a board up, writes a pidfile, prints the URL ───────────────────────
  FX1="$(mk_fx)"
  P1="$(freeport)"
  out_start="$( cd "$FX1" && COORD_PORT="$P1" bash "$JB" start 2>&1 )"; rc_start=$?

  [ "$rc_start" -eq 0 ] \
    && ok "ac16: jig-board.sh start exits 0" \
    || no "ac16: start exited $rc_start — an operator who asked for a board and did not get one must be told, but this is a failure to start"

  printf '%s' "$out_start" | grep -q "$P1" \
    && ok "ac16: start prints the board URL (port $P1)" \
    || no "ac16: start printed no URL — the one thing a human needs from this command is where to point a browser"

  PIDFILE="$FX1/.jig/board.pid"
  if [ -f "$PIDFILE" ]; then
    ok "ac16: the pidfile is written to .jig/board.pid"
    PID1="$(head -1 "$PIDFILE" 2>/dev/null || true)"
    _STARTED="$_STARTED $PID1"
    if [ -n "$PID1" ] && kill -0 "$PID1" 2>/dev/null; then
      ok "ac16: the recorded pid names a live process"
    else
      no "ac16: the pidfile names no live process — a stale pidfile is worse than none, it makes status lie"
    fi
  else
    no "ac16: no .jig/board.pid — stop and status have nothing to work from"
    PID1=""
  fi

  # The board must actually serve, not merely have been spawned.
  _n=0
  while [ "$_n" -lt 60 ]; do
    curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$P1/api/runs" && break
    _n=$((_n+1)); sleep 0.1
  done
  curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$P1/api/runs" \
    && ok "ac16: the board answers /api/runs on $P1" \
    || no "ac16: nothing is serving on $P1 — the process started but the coordinator is not up"

  # ── ac17 : idempotent start, honest status, clean stop ────────────────────────────────────
  out_start2="$( cd "$FX1" && COORD_PORT="$P1" bash "$JB" start 2>&1 )"; rc_start2=$?
  PID2="$(head -1 "$PIDFILE" 2>/dev/null || true)"
  [ "$rc_start2" -eq 0 ] && [ "$PID2" = "$PID1" ] \
    && ok "ac17: a second start is a no-op — same pid, exit 0" \
    || no "ac17: a second start exited $rc_start2 and moved the pid from '$PID1' to '$PID2' — two coordinators on one port is one coordinator and one crash"

  out_status="$( cd "$FX1" && COORD_PORT="$P1" bash "$JB" status 2>&1 )"; rc_status=$?
  [ "$rc_status" -eq 0 ] \
    && ok "ac17: status on a running board exits 0" \
    || no "ac17: status exited $rc_status on a running board"
  printf '%s' "$out_status" | grep -q "$P1" \
    && ok "ac17: status names the port" \
    || no "ac17: status does not name the port — 'running' without a URL is not an answer"

  ( cd "$FX1" && COORD_PORT="$P1" bash "$JB" stop >/dev/null 2>&1 )
  sleep 0.5
  if [ -n "$PID1" ] && kill -0 "$PID1" 2>/dev/null; then
    no "ac17: stop left the process alive — the port stays held and the next start collides"
  else
    ok "ac17: stop ends the process"
  fi

  ( cd "$FX1" && COORD_PORT="$P1" bash "$JB" stop >/dev/null 2>&1 )
  [ "$?" -eq 0 ] \
    && ok "ac17: stop with nothing running exits 0 (idempotent)" \
    || no "ac17: a second stop failed — teardown that errors on an already-clean state cannot be scripted"
fi

# ── ac18 : run-loop.sh --board wires a run to a board ────────────────────────────────────────
FX2="$(mk_fx)"
P2="$(freeport)"
probe_out="$FX2/probe.out"
out_board="$( cd "$FX2" && FX_PROBE_OUT="$probe_out" COORD_PORT="$P2" \
    env -u HARNESS_REPORT_URL bash "$RL" --board fx specs/fx 2>&1 )"; rc_board=$?
_p="$(head -1 "$FX2/.jig/board.pid" 2>/dev/null || true)"; _STARTED="$_STARTED $_p"

[ "$rc_board" -eq 0 ] \
  && ok "ac18: run-loop.sh --board completes its phases (rc=0)" \
  || no "ac18: --board run exited $rc_board — the flag must not change whether the run works"

printf '%s' "$out_board" | grep -q "$P2" \
  && ok "ac18: the board URL is printed before the phases" \
  || no "ac18: the run never printed the board URL — the operator has to guess where to look"

CONTROL_FIRED=0
if [ -f "$probe_out" ]; then
  if grep -q "REPORT_URL=\[http://127.0.0.1:$P2\]" "$probe_out"; then
    ok "ac18: the phase saw HARNESS_REPORT_URL pointing at the board"
    CONTROL_FIRED=1
  else
    no "ac18: the phase saw '$(cat "$probe_out")' — starting a board the run does not report to is a board with nothing on it"
  fi
else
  no "ac18: the probe never ran — the fixture strategy did not reach its build phase"
fi

# ── ac19 : no flag, no board, no export ─────────────────────────────────────────────────────
# The control is ac18 directly above: the same fixture and the same probe just recorded a
# non-empty value, so an empty one here is a finding rather than a broken probe.
FX3="$(mk_fx)"
probe_out3="$FX3/probe.out"
out_plain="$( cd "$FX3" && FX_PROBE_OUT="$probe_out3" \
    env -u HARNESS_REPORT_URL bash "$RL" fx specs/fx 2>&1 )"; rc_plain=$?

[ "$rc_plain" -eq 0 ] \
  && ok "ac19: the unflagged run still completes" \
  || no "ac19: the unflagged run exited $rc_plain — the flag's machinery leaked into the default path"

[ ! -e "$FX3/.jig/board.pid" ] \
  && ok "ac19: no board was started without --board" \
  || no "ac19: a board process was started without the flag — the default run path must start nothing"

# This assertion is only worth its PASS while its control holds. With ac18's probe never
# having read a non-empty value, "the phase saw nothing" is what a broken probe says too —
# so the credit is withheld rather than banked (Trap B; the red run banked it).
if [ "$CONTROL_FIRED" -ne 1 ]; then
  no "ac19: withheld — ac18's control never recorded a non-empty HARNESS_REPORT_URL, so an empty one here proves nothing"
elif [ -f "$probe_out3" ]; then
  grep -q 'REPORT_URL=\[\]' "$probe_out3" \
    && ok "ac19: the phase saw HARNESS_REPORT_URL unset, exactly as today (control: ac18 proved the probe reads it)" \
    || no "ac19: the phase saw '$(cat "$probe_out3")' — an unconfigured channel is not a degraded mode, and a run that silently reports somewhere is not the run it was"
else
  no "ac19: the probe never ran in the unflagged fixture"
fi

# ── ac20 : the operator surface is documented ───────────────────────────────────────────────
if [ -f "$DOC" ]; then
  grep -q 'jig-board.sh' "$DOC" \
    && ok "ac20: docs/coordinator.md documents jig-board.sh" \
    || no "ac20: docs/coordinator.md never mentions jig-board.sh — the doc still tells an operator to hand-start python3"
  grep -q -- '--board' "$DOC" \
    && ok "ac20: docs/coordinator.md documents the --board flag" \
    || no "ac20: docs/coordinator.md never mentions --board"
else
  no "ac20: docs/coordinator.md missing"
fi

gate_done
