#!/usr/bin/env bash
# specs/20260828b-index-nested-runs/verify.sh — the deterministic gate for "the index can see a
# run that lives one level deeper".
#
# BEHAVIOURAL. It builds a fixture corpus carrying ALL THREE layouts at once and runs the real
# loop-index.py over it, then asserts on the rows it emitted. The assertions were written against
# the tool's ACTUAL output, not an assumed schema: the first draft of this gate expected one row
# per run with a `pid` field, and the tool in fact emits one row per TASK with a `runs` array.
# A gate written from the assumed shape would have failed every correct implementation.
#
# harness_roots is also exercised DIRECTLY, by importing loop-index.py, because the scope a
# nested run reports is not visible in the rendered rows and outcome 5 is about exactly that.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"

# `bound`, not `timeout`: this gate is author-facing, so it runs on macOS as well as in the
# container, and macOS ships neither timeout nor gtimeout. scripts/bound.sh is the one
# implementation and prefers the real timeout where it exists. See specs/amendments.md,
# "Portability follows the invoker, not the tool".
# shellcheck source=/dev/null
. "$R/scripts/bound.sh"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

INDEX="$R/scripts/loop-index.py"
NEST="$R/specs/20260825b-evidence-spec-nesting/verify.sh"

[ -r "$INDEX" ] || { echo "  FAIL  scope: loop-index.py missing" >&2; exit 1; }
python3 -c "import sys; f=sys.argv[1]; compile(open(f).read(), f, 'exec')" "$INDEX" >/dev/null 2>&1 \
  || { echo "  FAIL  scope: loop-index.py does not compile" >&2; exit 1; }
ok "scope: loop-index.py exists and compiles"

_stray="$(find "$R/specs/20260828b-index-nested-runs" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec — re-run with TMPDIR=<exec-able dir>" >&2
                        echo "VERIFY: ENV" >&2; exit 2; }

# ── THE FIXTURE — all three layouts, side by side ──────────────────────────────────────────
# 1001 nested (<slug>/<host>/run), 2002 scoped (<slug>/run), 3003 flat (run). The two older
# layouts are the controls: a fix that sees the new one by ceasing to see them has moved the
# blindness, not cured it, and both exist in real corpora on disk.
P="$T/proj"
mkfix() { # mkfix <relpath-under-store> <pid>
  mkdir -p "$P/.evidence/runs/$1" "$(dirname "$P/.evidence/status/$1")"
  printf 'ralph(qwen): T1 — demo\nwrote a file\n' > "$P/.evidence/runs/$1/T1-attempt1.log"
  printf '{"agent":"qwen","pid":%s,"repo":"proj","branch":"b","spec":"demo","task":"T1: demo","task_index":1,"total_tasks":1,"attempt":1,"max_attempts":3,"phase":"done","verify_pass":true}\n' \
    "$2" > "$P/.evidence/status/$1.json"
}
mkfix "demo-spec/hostA/qwen-1001" 1001
mkfix "legacy-spec/qwen-2002"     2002
mkfix "qwen-3003"                 3003
git -C "$P" init -q 2>/dev/null; git -C "$P" config user.email g@e; git -C "$P" config user.name g
git -C "$P" add -A 2>/dev/null; git -C "$P" commit -qm base 2>/dev/null

python3 "$INDEX" --repo "$P" --jsonl "$T/out.jsonl" --out "$T/out.md" >/dev/null 2>&1
PIDS="$(python3 - "$T/out.jsonl" <<'PY' 2>/dev/null
import json,sys
seen=[]
for l in open(sys.argv[1]):
    l=l.strip()
    if not l: continue
    for r in json.loads(l).get("runs") or []:
        seen.append(str(r.get("pid")))
print(" ".join(sorted(set(seen))))
PY
)"
have(){ case " $PIDS " in *" $1 "*) return 0;; *) return 1;; esac; }

# The two controls FIRST: if they are broken the new assertion proves nothing.
have 2002 && ok "ac2: the scoped layout <slug>/<agent>-<pid> still enumerates (control)" \
           || no "ac2: the scoped layout stopped enumerating — the fix moved the blindness"
have 3003 && ok "ac3: the flat layout <agent>-<pid> still enumerates (control)" \
           || no "ac3: the flat layout stopped enumerating — the fix moved the blindness"

have 1001 && ok "ac1: a nested run <slug>/<host>/<agent>-<pid> is enumerated" \
           || pend "ac1: the nested layout is enumerated (seen: ${PIDS:-none})"

# ── AC-4 · the status store traverses too ──────────────────────────────────────────────────
# phase/verify_pass reach a row only from the status JSON, so their presence on the nested run
# is the join. This is why the fix belongs in harness_roots and not in glob_runs.
if have 1001; then
  _joined="$(python3 - "$T/out.jsonl" <<'PY' 2>/dev/null
import json,sys
for l in open(sys.argv[1]):
    l=l.strip()
    if not l: continue
    for r in json.loads(l).get("runs") or []:
        if str(r.get("pid"))=="1001":
            print("yes" if r.get("phase")=="done" and r.get("verify_pass") is True else "no")
PY
)"
  [ "$_joined" = yes ] && ok "ac4: the nested run's status JSON is joined to it (phase+verify_pass)" \
                       || no "ac4: the nested run has no status join — load_status is still blind"
else
  pend "ac4: the nested run's status JSON is joined"
fi

# ── AC-5/AC-6 · harness_roots directly — scope is the slug, the host is not a run ──────────
# PYTHONDONTWRITEBYTECODE: importing loop-index.py writes scripts/__pycache__/ into the
# worktree, and a gate that litters the tree it measures trips the next run's scope check.
_hr="$(PYTHONDONTWRITEBYTECODE=1 python3 - "$INDEX" "$P" <<'PY' 2>/dev/null
import importlib.util, sys, os
spec=importlib.util.spec_from_file_location("li", sys.argv[1])
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
base=os.path.join(sys.argv[2], ".evidence", "runs")
for path,scope in m.harness_roots(base):
    print(os.path.relpath(path, base), "|", scope)
PY
)"
if [ -z "$_hr" ]; then
  pend "ac5: harness_roots reports the nested root"
  pend "ac6: a host directory is not counted as a run"
else
  printf '%s\n' "$_hr" | grep -q '^demo-spec/hostA | demo-spec$' \
    && ok "ac5: the nested root reports scope=demo-spec — the slug, not the host" \
    || pend "ac5: scope for the nested root is not the slug ($(printf '%s' "$_hr" | tr '\n' ';'))"
  printf '%s\n' "$_hr" | grep -qE '\| *hostA$' \
    && no "ac6: a host directory was reported as the scope" \
    || ok "ac6: no host directory is treated as a scope or a run"
fi

# ── AC-8 · no empty husk survives the sweep ────────────────────────────────────────────────
# An expired spec's runs are reaped, leaving an empty host directory, which keeps the slug
# directory non-empty, which stops the slug directory being reaped. The husk is invisible until
# both prunes run in the right order — inner level first.
LG="$T/gc"; mkdir -p "$LG/expired-spec/hostA" "$LG/live-spec/hostB/qwen-9/x"
printf 'live\n' > "$LG/live-spec/hostB/qwen-9/f"
( ROOT="$P" SPEC_DIR="$P/specs/demo" RALPH_LOG_DIR="$LG" RALPH_AGENT=gate RALPH_HOST_ID=hostZ \
  bash -c '. "$0"; log_init >/dev/null 2>&1' "$R/scripts/ralph-log.sh" ) >/dev/null 2>&1
if [ -d "$LG/expired-spec" ]; then
  pend "ac8: an expired spec is left as an empty husk ($(ls -d "$LG/expired-spec"))"
else
  ok "ac8: the expired spec's empty host and slug directories are both swept"
fi
[ -d "$LG/live-spec/hostB/qwen-9" ] \
  && ok "control: a live run is untouched by the sweep — -empty is doing the discriminating" \
  || no "control: the sweep deleted a directory that still held a run"

# ── AC-9 · the reap was MOVED, not widened ─────────────────────────────────────────────────
# A legacy-layout run (<slug>/<agent>-<pid>, no host level) sits at a depth the new reap no
# longer visits, so it is never collected. The control below is the reason this cannot be fixed
# by simply reaping the shallower depth as well: a HOST directory also sits there, and its mtime
# tracks its newest child, so an aged host would be deleted wholesale — taking live runs with it.
RP="$T/reap"
mkdir -p "$RP/old-spec/qwen-777" "$RP/new-spec/hostQ/qwen-888"
printf 'x\n' > "$RP/old-spec/qwen-777/T1-attempt1.log"
printf 'y\n' > "$RP/new-spec/hostQ/qwen-888/T1-attempt1.log"
# age the legacy run AND the host dir; leave the run inside the host fresh
touch -t 202001010000 "$RP/old-spec/qwen-777/T1-attempt1.log" "$RP/old-spec/qwen-777" \
                      "$RP/new-spec/hostQ" 2>/dev/null
( ROOT="$P" SPEC_DIR="$P/specs/demo" RALPH_LOG_DIR="$RP" RALPH_AGENT=gate RALPH_HOST_ID=hostZ \
  bash -c '. "$0"; log_init >/dev/null 2>&1' "$R/scripts/ralph-log.sh" ) >/dev/null 2>&1
[ -d "$RP/old-spec/qwen-777" ] \
  && pend "ac9: an aged legacy-layout run is still never reaped" \
  || ok "ac9: an aged run in the older layout is reaped again"
[ -d "$RP/new-spec/hostQ/qwen-888" ] \
  && ok "control: a FRESH run under an AGED host directory survives — the host is not reaped wholesale" \
  || no "control: a live run was deleted with its aged host directory"

# ── AC-7 · the detector itself ─────────────────────────────────────────────────────────────
# This regression was caught by another spec's gate, two merges after it shipped. That gate is
# the detector, and it is only a detector while it is green for the right reason.
# Keyed on BOTH remaining tasks' artefacts, not just T2's. This check runs the WHOLE
# evidence-spec-nesting gate, which cannot be green until T3's reap and prune land too — so
# keying it on T2 alone made a CORRECT T2 unpassable, which is the exact defect the pend
# contract exists to prevent: a pend must key on the artefact of the task that satisfies it.
_t3_built(){ [ "$(sed 's/#.*//' "$R/scripts/ralph-log.sh" | grep -c 'empty -delete')" -ge 2 ]; }
if [ -r "$NEST" ]; then
  if grep -q 'maxdepth 3' "$NEST" 2>/dev/null && _t3_built; then
    if STRICT=1 bound 180 bash "$NEST" >/dev/null 2>&1; then
      ok "ac7: specs/20260825b-evidence-spec-nesting is green again"
    else
      no "ac7: evidence-spec-nesting is still red — the regression it detects is not fixed"
    fi
  else
    pend "ac7: evidence-spec-nesting green (needs T2's depth fix and T3's reap/prune)"
  fi
else
  no "ac7: specs/20260825b-evidence-spec-nesting/verify.sh is missing"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
