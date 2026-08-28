#!/usr/bin/env bash
# T06 — 20260828g migrated to the per-task layout. Gates only; T07 owns the mutants.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
G="$ROOT/specs/20260828g-dispatch-core"

n_dirs="$(ls -d "$G"/tasks/T0[1-5]-* 2>/dev/null | wc -l)"
if [ "$n_dirs" = 0 ]; then
  no "ac1: five task directories, each with task.md and verify.sh"
  no "ac2: each task.md carries its task text verbatim from tasks.txt"
  no "ac3: no task gate contains pend"
  no "ac4: every task gate passes against the merged implementation"
  no "ac5: scripts/dispatch/ is untouched by the migration"
  gate_done
fi

# ac1
miss=""
for i in 1 2 3 4 5; do
  d="$(ls -d "$G"/tasks/T0"$i"-* 2>/dev/null | head -1)"
  [ -n "$d" ] || { miss="$miss T0$i-missing"; continue; }
  [ -f "$d/task.md" ]   || miss="$miss T0$i/task.md"
  [ -f "$d/verify.sh" ] || miss="$miss T0$i/verify.sh"
done
[ -z "$miss" ] && ok "ac1: five task directories, each with task.md and verify.sh" \
               || no "ac1: layout incomplete —$miss (found $n_dirs of 5)"

# ac2 — verbatim. The task text is what the executor is given; a paraphrase in task.md means the
# gate and the prompt describe different work.
_v="$(timeout 30 python3 - "$G" <<'PY' 2>&1
import sys, pathlib, re
g = pathlib.Path(sys.argv[1])
paras = [p.strip() for p in g.joinpath("tasks.txt").read_text().split("\n\n") if p.strip()]
bad = []
for i, para in enumerate(paras[:5], 1):
    d = next(iter(sorted(g.glob(f"tasks/T0{i}-*"))), None)
    if d is None or not (d / "task.md").is_file():
        bad.append(f"T0{i}:absent"); continue
    got = (d / "task.md").read_text().strip()
    # the heading a task.md may carry is not part of the text
    got = re.sub(r"^#[^\n]*\n+", "", got).strip()
    if got != para:
        bad.append(f"T0{i}:differs")
print("ok" if not bad else "bad:" + ",".join(bad))
PY
)"
case "$_v" in
  ok)   ok "ac2: each task.md carries its task text verbatim from tasks.txt" ;;
  bad:*) no "ac2: task.md does not match tasks.txt for ${_v#bad:} — the gate and the prompt would describe different work" ;;
  *)    no "ac2: could not compare task.md against tasks.txt. Python said: $(printf '%s' "$_v" | tr '\n' ' ' | tail -c 200)" ;;
esac

# ac3 — the vocabulary has no pend, and a task gate has nothing to defer.
_p="$(grep -l '\bpend\b' "$G"/tasks/T0[1-5]-*/verify.sh 2>/dev/null | tr '\n' ' ')"
[ -z "$_p" ] && ok "ac3: no task gate contains pend" \
             || no "ac3: pend appears in a task gate: $_p"

# ac4 — the known-good control. dispatcher.py on this branch is merged and correct, so a task
# gate that fails it is wrong about the world rather than strict.
redd=""
for d in "$G"/tasks/T0[1-5]-*; do
  [ -f "$d/verify.sh" ] || continue
  out="$( cd "$ROOT" && timeout 120 bash "$d/verify.sh" 2>&1 )"; rc=$?
  [ "$rc" = 124 ] && { redd="$redd $(basename "$d"):hung"; continue; }
  [ "$rc" = 0 ] || redd="$redd $(basename "$d"):$(printf '%s' "$out" | grep -m1 '  FAIL' | cut -c1-70)"
done
[ -z "$redd" ] && ok "ac4: every task gate passes against the merged implementation" \
               || no "ac4: a task gate fails the known-good tree —$redd"

# ac5 — a migration that edits what it re-measures cannot tell you the new gates agree with the old.
if git -C "$ROOT" diff --quiet origin/main -- scripts/dispatch/ 2>/dev/null; then
  ok "ac5: scripts/dispatch/ is untouched by the migration"
else
  no "ac5: the migration changed scripts/dispatch/: $(git -C "$ROOT" diff --name-only origin/main -- scripts/dispatch/ | tr '\n' ' ')"
fi
gate_done
