#!/usr/bin/env bash
# specs/fleet-run-key/verify.sh — the deterministic gate for "a run key that survives two workers".
#
# FUNCTIONAL, NOT GREP-BASED. ralph-log.sh is sourceable, so this gate sources it, points it at a
# scratch evidence root, calls log_init, and asserts on the DIRECTORIES it produced. Grepping for
# the string "run-key.sh" would pass on a comment — TEMPLATE.md §11 Trap A.
#
# Three verdicts. `pend` is for a LATER task's deliverable, keyed on that task's OWN artifact.
# STRICT=1 promotes every pend.
#
# NOTE ON THE PENDS: this gate was validated against an EMPTY tree *and* against a stub — a
# run-key.sh that exists and prints, with nothing else built. The empty-tree pass alone cannot
# reach an assertion behind a presence guard, which is exactly how the AC-8 control in
# specs/evidence-replayable shipped broken and failed correct work three times
# (evidence/2026-08-27-ac8-control-stale-path.md). See evidence/2026-08-27-red-before-green.md.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

KEY="$R/scripts/run-key.sh"
LOG="$R/scripts/ralph-log.sh"
STAT="$R/scripts/ralph-status.sh"
DOCTOR="$R/scripts/loop-doctor.sh"
INDEX="$R/scripts/loop-index.py"

# ── SCOPE AND LITTER — FIRST, AND FATAL ────────────────────────────────────────────────────
for f in "$LOG" "$STAT" "$DOCTOR"; do
  [ -r "$f" ] || { echo "  FAIL  scope: $f missing — this gate cannot run" >&2; exit 1; }
  bash -n "$f" 2>/dev/null || { echo "  FAIL  scope: $f is not syntactically valid bash" >&2; exit 1; }
done
[ -r "$INDEX" ] || { echo "  FAIL  scope: $INDEX missing" >&2; exit 1; }
# compile() in memory, NOT py_compile: py_compile writes scripts/__pycache__/ into the worktree,
# and a gate that litters the tree it measures is a gate that fails the next scope check.
python3 -c "import sys; f=sys.argv[1]; compile(open(f).read(), f, 'exec')" "$INDEX" >/dev/null 2>&1 \
  || { echo "  FAIL  scope: loop-index.py does not compile" >&2; exit 1; }
ok "scope: the touched scripts exist and parse"

_stray="$(find "$R/specs/fleet-run-key" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

# TMPDIR preflight. A noexec TMPDIR makes every fixture mock exit 126 and this gate then reports
# a pile of failures naming the wrong file — the fourth instance of that class cost a full
# baseline run (see specs/judge-loop/verify.sh). Probed up front instead.
T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/execprobe"; chmod +x "$T/execprobe" 2>/dev/null
if ! "$T/execprobe" 2>/dev/null; then
  echo "  FAIL  ENV: TMPDIR ($TMPDIR${TMPDIR:+ }) is noexec — re-run with TMPDIR=<exec-able dir>" >&2
  echo "VERIFY: ENV" >&2; exit 2
fi

REPO="$T/repo"; mkdir -p "$REPO/.evidence"
git -C "$REPO" init -q 2>/dev/null; git -C "$REPO" config user.email g@e; git -C "$REPO" config user.name g
mkdir -p "$T/specs/fleet-run-key"

# probe <body> — source ralph-log.sh with a scratch root, run log_init, then the caller's body.
cat > "$T/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
. "$GATE_LOG_SH"
log_init >/dev/null 2>&1
printf '%s\n' "${LOG_DIR:-}" > "$GATE_OUT/logdir"
eval "$GATE_BODY"
exit 0
PROBE
probe() {
  # `env`, not an assignment prefix: bash recognises assignments BEFORE expanding words, so a
  # conditional ${2:+VAR=val} in that position is parsed as the COMMAND, not as an assignment,
  # and the probe never runs. Measured the hard way while validating this gate.
  env GATE_LOG_SH="$LOG" GATE_OUT="$T" GATE_BODY="${1:-:}" \
  ROOT="$REPO" SPEC_DIR="$T/specs/fleet-run-key" \
  RALPH_LOG_DIR="$T/ev" RALPH_AGENT=gate ${2:+RALPH_HOST_ID="$2"} \
  bash "$T/probe.sh" >/dev/null 2>&1
  _rc=$?
  D="$(cat "$T/logdir" 2>/dev/null)"
  return $_rc
}
has(){ [ -x "$KEY" ]; }

# ── T1 · the resolver ──────────────────────────────────────────────────────────────────────
if [ -f "$KEY" ]; then
  out="$(RALPH_HOST_ID=node-a bash "$KEY" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ "$out" = "node-a" ] \
    && ok "ac1: RALPH_HOST_ID wins, and a dash survives (a pod name is full of them)" \
    || no "ac1: RALPH_HOST_ID=node-a gave rc=$rc [$out]"

  out="$(RALPH_HOST_ID='a/b c:d' bash "$KEY" 2>/dev/null)"
  case "$out" in
    */*|*' '*|*:*) no "ac2: unsafe bytes survived sanitisation [$out]" ;;
    "")            no "ac2: sanitisation produced an empty discriminator" ;;
    *)             ok "ac2: unsafe bytes are replaced, not dropped ($out)" ;;
  esac

  # A FAILING `hostname`, not an empty PATH. Emptying PATH also removes `tr`, so the resolver
  # could not satisfy the check under any implementation — an unsatisfiable assertion is a broken
  # control, not a strict one (specs/evidence-replayable/evidence/2026-08-27-ac8-control-stale-path.md).
  mkdir -p "$T/nohost"; printf '#!/bin/sh\nexit 1\n' > "$T/nohost/hostname"; chmod +x "$T/nohost/hostname"
  out="$(RALPH_HOST_ID='' PATH="$T/nohost:$PATH" bash "$KEY" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] && [ -n "$out" ] \
    && ok "ac3: a failing hostname still yields a discriminator, rc 0 ($out)" \
    || no "ac3: empty RALPH_HOST_ID and a failing hostname gave rc=$rc [$out] — a discriminator that can fail is a loop that can fail"

  out="$(bash "$KEY" 2>/dev/null)"
  [ -n "$out" ] && ok "ac3: a bare call yields a discriminator ($out)" \
                || no "ac3: a bare call printed nothing"
else
  pend "ac1: run-key.sh honours RALPH_HOST_ID"
  pend "ac2: run-key.sh sanitises"
  pend "ac3: run-key.sh never fails"
fi

# ── T2 · the layout ────────────────────────────────────────────────────────────────────────
D=""; probe ':' "node-a" || true
if [ -z "$D" ] || [ ! -d "$D" ]; then
  no "harness: log_init produced no run directory — nothing below can be measured"
else
  ok "harness: log_init honours RALPH_LOG_DIR and creates a run directory"

  # AC-10 of specs/evidence-replayable, asserted here as a REGRESSION GUARD: this spec is the
  # one most likely to break it, so it is measured here rather than assumed.
  case "$(basename "$D")" in
    gate-[0-9]*) ok "ac4: the leaf is still <agent>-<pid> ($(basename "$D")) — evidence-replayable AC-10 holds" ;;
    *)           no "ac4: the leaf is '$(basename "$D")', not <agent>-<pid> — this breaks every reader and AC-10" ;;
  esac

  if [ "$(basename "$(dirname "$D")")" = "node-a" ]; then
    ok "ac5: the host level sits between the spec slug and the run"
  else
    pend "ac5: the host directory level (parent is '$(basename "$(dirname "$D")")')"
  fi

  # AC-9 of specs/evidence-replayable, same reasoning: a regression guard, not an assumption.
  LATEST="$(dirname "$D")/latest"
  if [ -L "$LATEST" ]; then
    tgt="$(readlink "$LATEST" 2>/dev/null)"
    case "$tgt" in
      */*) no "ac6: latest -> '$tgt' is a path, not a sibling basename — evidence-replayable AC-9 broken" ;;
      *)   [ "$tgt" = "$(basename "$D")" ] \
             && ok "ac6: latest is still a slash-free sibling symlink ($tgt) — AC-9 holds" \
             || no "ac6: latest -> '$tgt' but the newest run is '$(basename "$D")'" ;;
    esac
  else
    pend "ac6: latest beside the run dir"
  fi
fi

# ── AC-7 · THE POINT — one pid, two hosts, two directories ─────────────────────────────────
# Both log_init calls happen in ONE process, so $$ is IDENTICAL by construction. That is the
# collision fleet-dispatch §6 describes, reproduced exactly rather than approximated.
cat > "$T/twohost.sh" <<'TWO'
#!/usr/bin/env bash
set -uo pipefail
. "$GATE_LOG_SH"
RALPH_HOST_ID=node-a log_init >/dev/null 2>&1; d1="${LOG_DIR:-}"
RALPH_HOST_ID=node-b log_init >/dev/null 2>&1; d2="${LOG_DIR:-}"
printf '%s\n%s\n%s\n' "$d1" "$d2" "$$" > "$GATE_OUT/two"
exit 0
TWO
GATE_LOG_SH="$LOG" GATE_OUT="$T" ROOT="$REPO" SPEC_DIR="$T/specs/fleet-run-key" \
  RALPH_LOG_DIR="$T/ev2" RALPH_AGENT=gate bash "$T/twohost.sh" >/dev/null 2>&1
d1="$(sed -n 1p "$T/two" 2>/dev/null)"; d2="$(sed -n 2p "$T/two" 2>/dev/null)"
if [ -n "$d1" ] && [ -n "$d2" ]; then
  if [ "$(basename "$d1")" = "$(basename "$d2")" ]; then
    ok "control: both runs share a pid, so the leaf alone cannot separate them ($(basename "$d1"))"
  else
    no "control: the two probes did not share a pid — AC-7 below would prove nothing"
  fi
  [ "$d1" != "$d2" ] \
    && ok "ac7: one pid on two hosts yields two run directories — the corpus cannot be silently merged" \
    || pend "ac7: two hosts still collide on '$d1'"
else
  pend "ac7: one pid on two hosts"
fi

# ── T3 · the status file ───────────────────────────────────────────────────────────────────
if grep -q 'run-key' "$STAT" 2>/dev/null; then
  ( RALPH_STATUS_DIR="$T/st" ROOT="$REPO" SPEC_DIR="$T/specs/fleet-run-key" \
    RALPH_AGENT=gate RALPH_HOST_ID=node-a \
    bash -c '. "$0"; hb_init 2>/dev/null || true; hb_write running 2>/dev/null || true' "$STAT" ) >/dev/null 2>&1
  sf="$(find "$T/st" -name '*.json' 2>/dev/null | head -1)"
  if [ -n "$sf" ]; then
    case "$(basename "$sf")" in
      gate-[0-9]*.json) ok "ac8: the status file basename is still <agent>-<pid>.json" ;;
      *) no "ac8: status basename is '$(basename "$sf")', not <agent>-<pid>.json" ;;
    esac
    [ "$(basename "$(dirname "$sf")")" = "node-a" ] \
      && ok "ac8: the status file sits under the host level too" \
      || no "ac8: status parent is '$(basename "$(dirname "$sf")")', not the host"
    jq -e 'has("pid") and (.pid|type=="number")' "$sf" >/dev/null 2>&1 \
      && ok "ac9: pid is still an unquoted JSON number — the corpus format did not shift" \
      || no "ac9: pid is no longer a JSON number; this spec must not change that"
  else
    pend "ac8: the status file under the host level"
    pend "ac9: pid stays a JSON number"
  fi
else
  pend "ac8: the status file under the host level"
  pend "ac9: pid stays a JSON number"
fi

# ── T4 · the record ────────────────────────────────────────────────────────────────────────
if grep -q 'run_key' "$LOG" 2>/dev/null; then
  probe 'log_meta T1 1' "node-a" || true
  f="$D/T1-attempt1.json"
  if [ -f "$f" ]; then
    if jq -e 'has("host") and has("run_key")' "$f" >/dev/null 2>&1; then
      ok "ac10: the record carries host and run_key"
      jq -e '(.host|type=="string") and (.run_key|type=="string")' "$f" >/dev/null 2>&1 \
        && ok "ac10: both are strings, never null" \
        || no "ac10: host/run_key are not both strings"
      want="node-a/$(basename "$D")"
      [ "$(jq -r '.run_key' "$f" 2>/dev/null)" = "$want" ] \
        && ok "ac11: run_key is <host>/<agent>-<pid> ($want)" \
        || no "ac11: run_key is '$(jq -r '.run_key' "$f" 2>/dev/null)', expected '$want'"
      [ "$(jq -r '.run_id' "$f" 2>/dev/null)" = "$(basename "$D")" ] \
        && ok "ac11: run_id still means the leaf — an identity was added, not replaced" \
        || no "ac11: run_id changed meaning; the existing readers join on it"
    else
      no "ac10: the record is missing host and/or run_key"
    fi
  else
    pend "ac10: host and run_key in the record"
    pend "ac11: run_key shape"
  fi
else
  pend "ac10: host and run_key in the record"
  pend "ac11: run_key shape"
fi

# ── T5 · the readers ───────────────────────────────────────────────────────────────────────
# The host directory is named `harness-run-7` ON PURPOSE: a real k8s pod name that MATCHES
# loop-doctor's own run-id glob. Excluding the level by name cannot work; only position can.
FX="$T/fx"; mkdir -p "$FX/logs/demo/harness-run-7/qwen-4242" "$FX/status/demo/harness-run-7"
printf 'transcript\n' > "$FX/logs/demo/harness-run-7/qwen-4242/T1-attempt1.log"
printf 'diff\n'       > "$FX/logs/demo/harness-run-7/qwen-4242/T1-attempt1.diff"
printf '{"agent":"qwen","pid":4242,"repo":"r","branch":"b","spec":"demo","task":"T1","task_index":1,"total_tasks":1,"attempt":1,"phase":"running"}\n' \
  > "$FX/status/demo/harness-run-7/qwen-4242.json"

case "harness-run-7" in
  [a-z0-9]*-[0-9]*) ok "control: the host name 'harness-run-7' DOES match the run-id glob — ac12 is a real requirement" ;;
  *) no "control: the fixture host name does not match the glob, so ac12 proves nothing" ;;
esac

dj="$(bash "$DOCTOR" --json --log-dir "$FX/logs" --status-dir "$FX/status" 2>/dev/null)"
if [ -n "$dj" ] && printf '%s' "$dj" | jq -e . >/dev/null 2>&1; then
  n="$(printf '%s' "$dj" | jq -s 'length' 2>/dev/null)"
  if [ "$n" = 1 ]; then
    ok "ac12: loop-doctor sees exactly one run — the host directory is not counted as one"
    up="$(printf '%s' "$dj" | jq -s '[.[].unparsed]|add' 2>/dev/null)"
    [ "$up" = 0 ] \
      && ok "ac13: a healthy run at the new depth still reports unparsed=0" \
      || no "ac13: unparsed=$up at the new depth — the reader sees format drift where there is none"
  else
    pend "ac12: loop-doctor counts $n runs at the new depth, expected 1"
    pend "ac13: unparsed=0 at the new depth"
  fi
else
  pend "ac12: loop-doctor reads the new depth"
  pend "ac13: unparsed=0 at the new depth"
fi

# ── AC-14 · nothing here may fail a loop ───────────────────────────────────────────────────
if [ "$(id -u)" = 0 ]; then
  pend "ac14: cannot test an unwritable LOG_DIR as root"
else
  UW="$T/unwritable"; mkdir -p "$UW"; chmod 500 "$UW" 2>/dev/null
  GATE_LOG_SH="$LOG" GATE_OUT="$T" ROOT="$REPO" SPEC_DIR="$T/specs/fleet-run-key" \
    RALPH_LOG_DIR="$UW/ev" RALPH_AGENT=gate RALPH_HOST_ID=node-a \
    GATE_BODY='for w in log_prompt log_gate log_patch log_meta; do type "$w" >/dev/null 2>&1 && "$w" T1 1 x 0 >/dev/null 2>&1 || true; done' \
    bash "$T/probe.sh" >/dev/null 2>&1
  rc=$?
  chmod 700 "$UW" 2>/dev/null
  [ "$rc" = 0 ] \
    && ok "ac14: the writers still exit 0 against an unwritable LOG_DIR" \
    || no "ac14: a writer returned $rc against an unwritable LOG_DIR — it can fail the loop"
fi

# ── AC-15 · the GC still reaps runs, and never a host ──────────────────────────────────────
GC="$T/gc"; mkdir -p "$GC/demo/node-a/qwen-1/sub" "$GC/demo/node-a/qwen-2"
printf 'x\n' > "$GC/demo/node-a/qwen-1/f"
find "$GC/demo/node-a/qwen-1" -exec touch -t 202001010000 {} + 2>/dev/null
if grep -qE 'mindepth 3 -maxdepth 3|maxdepth 3' "$LOG" 2>/dev/null; then
  ( ROOT="$REPO" RALPH_LOG_DIR="$GC" RALPH_AGENT=gate RALPH_HOST_ID=node-a \
    bash -c '. "$0"; log_init >/dev/null 2>&1' "$LOG" ) >/dev/null 2>&1
  [ -d "$GC/demo/node-a" ] \
    && ok "ac15: the GC left the host directory standing" \
    || no "ac15: the GC deleted the host directory — one rm -rf per host, on an mtime it never meant to test"
  [ ! -d "$GC/demo/node-a/qwen-1" ] \
    && ok "ac15: the GC still reaps a stale run at the new depth" \
    || pend "ac15: the GC reaps a stale run at depth 3"
else
  pend "ac15: the GC depth moves with the layout"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
