# MUTANT: ac2
# TARGET: scripts/work-mutate.sh
# WHY: the site label embeds the scratch workspace path — helpful in exactly one log, and
# WHY: now every run's probe lines differ, so no recorded row can ever be reproduced by
# WHY: re-running the tool at its commit.
#!/usr/bin/env bash
# work-mutate.sh — probe a task gate's sensitivity against the WORK it just blessed.
#
#   scripts/work-mutate.sh <task-dir> [--commit <sha>]     (run from the repo root)
#
# The author-independent half of gate rigor (specs/20260831v-work-mutation). A mutant
# corpus tests the defects the gate's author imagined; this tool derives probes from the
# executor's ACTUAL commit — revert one hunk, drop one added line — applies each in a
# hermetic copy materialised AT that commit, and re-runs the task's gate. A gate that
# keeps passing while the work it certified is dismantled is measurably insensitive to
# that work.
#
# TELEMETRY, NOT ENFORCEMENT — the founding posture, and why the vocabulary never
# overlaps gate-selftest's:
#   NOTICED    the gate exited non-zero against the damaged work
#   UNNOTICED  the gate passed the damaged work — a LEAD, not a conviction (dropping an
#              inert line SHOULD go unnoticed; the equivalent-mutant problem is why an
#              UNNOTICED probe never fails anything)
#   HUNG       the gate never returned inside the bound
# The tool exits 0 unless the TOOL itself errs. Verdicts are data.
#
# DETERMINISTIC: probes are ordered by their position in the diff and sampled by a seed
# derived from the commit sha, so any recorded row is reproducible by re-running the tool
# at that commit. RALPH_WORK_MUTANTS caps the count (default 4; 0 generates nothing).
#
# Emission rides the 20260830f seam: SELFTEST_EVID set => one JSONL row per probe plus a
# run_complete marker into $SELFTEST_EVID/worksens-<spec-slug>.jsonl; unset => not one
# byte. Every row carries "kind":"work" so telemetry can never be mistaken for the
# corpus enforcement record.
#
# .evidence/ paths are excluded from probe generation: the loop's own status rows ride
# task commits, and probing the harness's bookkeeping tells the researcher nothing about
# the gate's view of the WORK.
set -uo pipefail

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bound.sh"

usage(){ echo "usage: work-mutate.sh <task-dir> [--commit <sha>]" >&2; }

TASK_DIR=""
COMMIT="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) [ $# -ge 2 ] || { usage; exit 1; }; COMMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 1 ;;
    *) if [ -z "$TASK_DIR" ]; then TASK_DIR="$1"; shift
       else usage; exit 1; fi ;;
  esac
done
[ -n "$TASK_DIR" ] || { usage; exit 1; }

BUDGET="${RALPH_WORK_MUTANTS:-4}"
case "$BUDGET" in ''|*[!0-9]*) echo "error: RALPH_WORK_MUTANTS must be a number, got '$BUDGET'" >&2; exit 1 ;; esac
if [ "$BUDGET" = "0" ]; then
  echo "work-mutate: budget 0 — no probes generated"
  exit 0
fi

if [[ "$TASK_DIR" != /* ]]; then TASK_DIR="$(pwd)/$TASK_DIR"; fi
[ -d "$TASK_DIR" ] || { echo "error: task directory does not exist: $TASK_DIR" >&2; exit 1; }
TASK_DIR="$(cd "$TASK_DIR" && pwd -P)"
[ -f "$TASK_DIR/verify.sh" ] || { echo "error: no verify.sh in $TASK_DIR" >&2; exit 1; }

CWD="$(pwd)"
REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "error: not inside a git repository" >&2; exit 1; }
SHA="$(git -C "$REPO_ROOT" rev-parse --verify "$COMMIT" 2>/dev/null)" \
  || { echo "error: cannot resolve commit '$COMMIT'" >&2; exit 1; }
TASK_REL="${TASK_DIR#$REPO_ROOT}"

# spec slug from .../specs/<slug>/tasks/T<NN>-<x>
SPEC_SLUG="$(printf '%s' "$TASK_REL" | sed -n 's|.*/specs/\([^/]*\)/tasks/.*|\1|p')"
[ -n "$SPEC_SLUG" ] || SPEC_SLUG="unknown"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── hermetic copy AT the commit ─────────────────────────────────────────────────────────────
# git archive, not cp: the commit is the unit of trust the gate blessed and the unit a row
# can be reproduced from — the working tree may already have drifted past it. The copy gets
# its own fresh history (mutants must never reach real history) plus origin/main
# best-effort, for the same reason gate-selftest carries it: gates are entitled to compare
# against it, and an absent ref turns every probe into an environmental artifact.
mkdir -p "$T/worktree"
git -C "$REPO_ROOT" archive "$SHA" | tar -x -C "$T/worktree" \
  || { echo "error: could not materialise $SHA" >&2; exit 1; }
( cd "$T/worktree" \
  && git init -q . && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init ) \
  || { echo "error: could not init the hermetic copy" >&2; exit 1; }
( cd "$T/worktree" && git fetch -q "$REPO_ROOT" 'refs/remotes/origin/main:refs/remotes/origin/main' 2>/dev/null ) || true

TASK_PATH="$T/worktree$TASK_REL"
[ -f "$TASK_PATH/verify.sh" ] || { echo "error: verify.sh not present at $SHA ($TASK_REL)" >&2; exit 1; }

# ── probe generation: deterministic, from the commit's own diff ─────────────────────────────
git -C "$REPO_ROOT" show --format= --no-color "$SHA" > "$T/commit.diff" \
  || { echo "error: could not read the commit diff" >&2; exit 1; }

# Manifest lines: idx<TAB>operator<TAB>file<TAB>site<TAB>payload
#   revert-hunk: payload = path of a single-hunk patch file (reverse-applied)
#   drop-line:   payload = 1-based line number in the file AT the commit
python3 - "$T/commit.diff" "$T" "$SHA" "$BUDGET" > "$T/manifest" <<'PY' \
  || { echo "error: probe generation failed" >&2; exit 1; }
import random, re, sys

diff_path, tdir, sha, budget = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
raw = open(diff_path, encoding="utf-8", errors="replace").read()

INERT = re.compile(r'^\s*($|#|//|--(\s|$)|;)')   # blank / comment-only: probing these is noise

probes = []  # (op, file, site, payload)
cur_file, cur_header, hunk_lines, hunk_no = None, [], [], 0

def flush_hunk():
    global hunk_lines
    if cur_file and hunk_lines and not cur_file.startswith(".evidence/"):
        p = "%s/probe-%d.patch" % (tdir, len(probes))
        with open(p, "w", encoding="utf-8") as f:
            f.write("\n".join(cur_header) + "\n" + "\n".join(hunk_lines) + "\n")
        probes.append(("revert-hunk", cur_file, "hunk-%d@%s" % (hunk_no, tdir), p))
        # drop-one-added-line probes for this hunk, positioned in NEW-file numbering
        m = re.match(r'@@ -\d+(?:,\d+)? \+(\d+)', hunk_lines[0])
        new_ln = int(m.group(1)) - 1 if m else 0
        for l in hunk_lines[1:]:
            if l.startswith("+"):
                new_ln += 1
                if not INERT.match(l[1:]):
                    probes.append(("drop-line", cur_file, "line-%d" % new_ln, str(new_ln)))
            elif l.startswith("-"):
                pass
            else:
                new_ln += 1
    hunk_lines = []

for line in raw.splitlines():
    if line.startswith("diff --git"):
        flush_hunk()
        cur_file, cur_header, hunk_no = None, [line], 0
    elif line.startswith(("index ", "new file", "deleted file", "old mode", "new mode",
                          "similarity", "rename ", "copy ", "Binary files", "--- ", "+++ ")):
        cur_header.append(line)
        m = re.match(r'\+\+\+ b/(.*)$', line)
        if m:
            cur_file = m.group(1)
    elif line.startswith("@@"):
        flush_hunk()
        hunk_no += 1
        hunk_lines = [line]
    elif hunk_lines:
        hunk_lines.append(line)
flush_hunk()

# deterministic sample: seeded by the commit, original diff order preserved
if len(probes) > budget:
    idx = sorted(random.Random(int(sha[:8], 16)).sample(range(len(probes)), budget))
    probes = [probes[i] for i in idx]

for i, (op, f, site, payload) in enumerate(probes):
    print("%d\t%s\t%s\t%s\t%s" % (i, op, f, site, payload))
PY

NPROBES="$(grep -c . "$T/manifest" 2>/dev/null || echo 0)"
if [ "$NPROBES" = "0" ]; then
  echo "work-mutate: commit $SHA yields no probes (empty or fully inert diff)"
  echo "work-sensitivity: 0/0 noticed"
  exit 0
fi

# ── emission setup (20260830f discipline: unset means not one byte) ─────────────────────────
EVID="${SELFTEST_EVID:-}"
EVID_FILE=""
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ).$$"
if [ -n "$EVID" ]; then
  mkdir -p "$EVID" || { echo "error: cannot create SELFTEST_EVID dir: $EVID" >&2; exit 1; }
  EVID_FILE="$EVID/worksens-$SPEC_SLUG.jsonl"
fi

emit_row(){ # <operator> <file> <site> <verdict> <rc> <diff-file>
  [ -n "$EVID_FILE" ] || return 0
  python3 - "$EVID_FILE" "$RUN_ID" "$SPEC_SLUG" "$(basename "$TASK_DIR")" "$SHA" "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import json, sys, time
f, run, spec, task, sha, op, tgt, site, verdict, rc, diff_f = sys.argv[1:12]
try:
    diff = open(diff_f, encoding="utf-8", errors="replace").read()
except OSError:
    diff = ""
row = dict(ts=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), run_id=run, spec=spec,
           task=task, commit=sha, operator=op, target=tgt, site=site, verdict=verdict,
           gate_rc=int(rc), diff=diff, kind="work")
with open(f, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}

GATE_TIMEOUT="${GATE_SELFTEST_TIMEOUT:-30}"
NOTICED=0; UNNOTICED=0; HUNG=0

while IFS="$(printf '\t')" read -r idx op file site payload; do
  # apply the probe
  applied=1
  case "$op" in
    revert-hunk)
      ( cd "$T/worktree" && git apply --reverse "$payload" 2>/dev/null ) || applied=0
      cp "$payload" "$T/probe-diff" 2>/dev/null || : > "$T/probe-diff"
      ;;
    drop-line)
      python3 - "$T/worktree/$file" "$payload" "$T/probe-diff" <<'PY' || applied=0
import sys
path, ln, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
lines = open(path, encoding="utf-8", errors="replace").readlines()
if not (1 <= ln <= len(lines)):
    raise SystemExit(1)
dropped = lines[ln - 1]
del lines[ln - 1]
open(path, "w", encoding="utf-8").writelines(lines)
open(out, "w", encoding="utf-8").write("-" + dropped)
PY
      ;;
  esac
  if [ "$applied" = "0" ]; then
    # A probe that cannot apply is a tool artifact, never a verdict — say so and move on.
    echo "$op@$file[$site]: SKIPPED — probe did not apply"
    continue
  fi

  gate_out="$( cd "$T/worktree" && bound "$GATE_TIMEOUT" bash "$TASK_PATH/verify.sh" 2>&1 )"
  rc=$?

  # restore the copy to the commit state before the next probe
  ( cd "$T/worktree" && git checkout -q -- . && git clean -qfd ) || true

  if [ "$rc" = "124" ]; then
    verdict="HUNG"; HUNG=$((HUNG + 1))
  elif [ "$rc" = "0" ]; then
    verdict="UNNOTICED"; UNNOTICED=$((UNNOTICED + 1))
  else
    verdict="NOTICED"; NOTICED=$((NOTICED + 1))
  fi
  echo "$op@$file[$site]: $verdict"
  emit_row "$op" "$file" "$site" "$verdict" "$rc" "$T/probe-diff"
done < "$T/manifest"

TOTAL=$((NOTICED + UNNOTICED + HUNG))
echo "summary: noticed=$NOTICED unnoticed=$UNNOTICED hung=$HUNG probes=$TOTAL"
echo "work-sensitivity: $NOTICED/$TOTAL noticed"

if [ -n "$EVID_FILE" ]; then
  printf '{"run_complete":true,"run_id":"%s","spec":"%s","task":"%s","commit":"%s","noticed":%d,"unnoticed":%d,"hung":%d,"kind":"work"}\n' \
    "$RUN_ID" "$SPEC_SLUG" "$(basename "$TASK_DIR")" "$SHA" "$NOTICED" "$UNNOTICED" "$HUNG" >> "$EVID_FILE"
fi

exit 0
