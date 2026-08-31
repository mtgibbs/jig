#!/usr/bin/env bash
# Gate for 20260831l-loop-runs-from-snapshot. Single-task spec: one gate, no pend.
# The fixture repo carries its OWN copy of the harness scripts; the stub rewrites the
# fixture's running ralph-build.sh in place (same inode — a rename swap would test
# nothing, bash keeps reading the old inode via its fd). Red today: bash resumes at a
# displaced byte offset and executes fragments.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

mk_fx() { # <task-gate-body> — fixture with its own harness copy under scripts/
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx/tasks/T01-thing" "$d/fxtmp"
  cp -R "$R/scripts" "$d/scripts"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: do the thing' > "$d/specs/fx/tasks.txt"
  printf '.evidence/runs/\n' > "$d/.gitignore"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/specs/fx/tasks/T01-thing/verify.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/specs/fx/verify.sh"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

mk_stub() { # <body> -> path
  local s; s="$(mktemp)"; _FX="$_FX $s"
  printf '#!/usr/bin/env bash\n: "${ROOT:?}"\n%s\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' "$1" > "$s"
  printf '%s' "$s"
}

run_fx() { # <dir> <stub> — runs the FIXTURE's harness copy, TMPDIR captive
  local d="$1" s="$2"
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
      -u RALPH_NO_SNAPSHOT TMPDIR="$d/fxtmp" \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=120 \
      RALPH_EXEC_CMD="bash $s" bash "$d/scripts/ralph-build.sh" specs/fx 2>&1 )
}

# ── the self-edit fixture: the task IS rewriting the running loop script ──
# Same-inode rewrite: build the new content in a temp file, then `cat > target`
# (truncate + write through the existing inode). ~24KB of prefix so every later
# read offset lands in displaced content.
GATE_SELFEDIT='grep -q RALPH-FX-SELF-EDIT-MARKER "$(git rev-parse --show-toplevel)/scripts/ralph-build.sh" || { echo "  FAIL  fx: marker missing" >&2; exit 1; }; echo "  PASS  fx: marker present"; exit 0'
STUB_SELFEDIT='rb="$ROOT/scripts/ralph-build.sh"
new="$(mktemp)"
{ echo "#!/usr/bin/env bash"
  echo "# RALPH-FX-SELF-EDIT-MARKER"
  for i in $(seq 1 400); do echo "# padding line $i — displaces every saved byte offset in the reader"; done
  tail -n +2 "$rb"
} > "$new"
cat "$new" > "$rb"   # SAME INODE — the write bash is reading through
rm -f "$new"'

FX1="$(mk_fx "$GATE_SELFEDIT")"
S1="$(mk_stub "$STUB_SELFEDIT")"
out1="$(run_fx "$FX1" "$S1")"; rc1=$?

# ── ac1: the run survives its own rewrite ──
[ "$rc1" -eq 0 ] \
  && ok "ac1: the self-editing run exits 0" \
  || no "ac1: the run died (rc=$rc1) — $(printf '%s' "$out1" | grep -E 'command not found|syntax error|✗|STOP' | head -2 | tr '\n' ' ')"

# ── ac2: no displaced-fragment noise ──
printf '%s' "$out1" | grep -Eq 'command not found|syntax error' \
  && no "ac2: displaced fragments executed: $(printf '%s' "$out1" | grep -E 'command not found|syntax error' | head -1)" \
  || ok "ac2: no 'command not found' / 'syntax error' in the run output"

# ── ac3: the work landed — commit made, worktree copy edited ──
_n1="$(git -C "$FX1" rev-list --count HEAD)"
[ "$_n1" -eq 2 ] \
  && ok "ac3: the task's commit landed" \
  || no "ac3: expected 2 commits, found $_n1"
grep -q 'RALPH-FX-SELF-EDIT-MARKER' "$FX1/scripts/ralph-build.sh" \
  && ok "ac3: the worktree's loop script carries the edit (the deliverable)" \
  || no "ac3: the worktree copy lost the edit"

# ── ac4: no snapshot litter (TMPDIR was captive to the fixture) ──
_snaps="$(find "$FX1/fxtmp" -maxdepth 1 -name 'ralph-snap.*' 2>/dev/null)"
[ -z "$_snaps" ] \
  && ok "ac4: no ralph-snap.* left behind after the run" \
  || no "ac4: snapshot litter remains: $_snaps"

# ── ac4b: an EARLY exit (validation, before the main trap line) must not leak either ──
# Found live: the first implementation cleaned up only via the hb_tick_stop trap, and every
# exit-3/exit-1 path before that line leaked a snapshot per run.
out1b="$( cd "$FX1" && env -u RALPH_NO_SNAPSHOT TMPDIR="$FX1/fxtmp" \
  bash "$FX1/scripts/ralph-build.sh" specs/does-not-exist 2>&1 )"; rc1b=$?
[ "$rc1b" -ne 0 ] || no "ac4b: the missing-spec control unexpectedly passed"
_snaps="$(find "$FX1/fxtmp" -maxdepth 1 -name 'ralph-snap.*' 2>/dev/null)"
[ -z "$_snaps" ] \
  && ok "ac4b: an early exit leaves no snapshot behind" \
  || no "ac4b: early-exit snapshot litter: $_snaps"

# ── ac5: control — a normal run under the snapshot still passes ──
GATE_PLAIN='grep -q done "$(git rev-parse --show-toplevel)/ok.txt" 2>/dev/null || { echo "  FAIL  fx: ok.txt missing" >&2; exit 1; }; echo "  PASS  fx: ok.txt present"; exit 0'
FX2="$(mk_fx "$GATE_PLAIN")"
S2="$(mk_stub 'echo done > "$ROOT/ok.txt"')"
out2="$(run_fx "$FX2" "$S2")"; rc2=$?
[ "$rc2" -eq 0 ] \
  && ok "ac5: control — a plain run passes end-to-end (rc=0)" \
  || no "ac5: control broke (rc=$rc2) — $(printf '%s' "$out2" | grep -E 'FAIL|✗' | head -2 | tr '\n' ' ')"

# ── ac6 ──
bash -n "$R/scripts/ralph-build.sh" \
  && ok "ac6: ralph-build.sh passes bash -n" \
  || no "ac6: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
