# fixtures.sh — a throwaway loop with LOGGING ON, plus a stub coordinator that keeps whole bodies.
#
# Reuses the worker-channel fixture repo and executor rather than cloning them: that spec's
# mkloop/mkexec already build a two-task repo carrying the real scripts/, and a second copy would
# drift from it. What is NOT reused is runloop — it runs with RALPH_LOG=off, and this spec is
# entirely about the artifacts that logging produces, so reusing it would test nothing.
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"

COORD_PY="$ROOT/specs/20260828o-evidence-egress/lib/coord.py"

coord_start() {
  # Clear the port file FIRST. The readiness wait is `while [ ! -s coord.port ]`, so a stale file
  # from a previous coord_start satisfies it instantly and COORD_URL is set to a server that has
  # already been killed — after which every post silently goes nowhere and the gate blames the
  # implementation. This cost one false FAIL against a correct reference implementation.
  : > "$T/coord.log"; rm -rf "$T/coord.log.d"; rm -f "$T/coord.port"
  python3 "$COORD_PY" "$T/coord.log" > "$T/coord.port" 2>"$T/coord.err" &
  COORD_PID=$!
  local i=0
  while [ ! -s "$T/coord.port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  COORD_URL="http://127.0.0.1:$(cat "$T/coord.port" 2>/dev/null)"
}

# runloop_logged <dir> [env...] — like runloop, but with the evidence writer ENABLED.
runloop_logged() {
  local d="$1"; shift; local tag; tag="$(basename "$d")"
  ( cd "$d" && env "$@" RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
      timeout 180 bash scripts/ralph-build.sh specs/fx ) > "$T/$tag.out" 2>&1
  RC=$?
}

# arts <kind> — how many artifact posts of one kind arrived. Exactly one integer, always.
#
# `grep -c ... || echo 0` is the obvious idiom and is WRONG: grep -c PRINTS 0 and EXITS 1 when it
# matches nothing, so the fallback fires as well and the caller receives two lines. Every numeric
# test against that value then errors, and `[ ... ]` failing sends an if/elif chain to its else —
# which is the PASS branch. Two assertions in this gate reported PASS against an implementation
# that did not exist because of it.
arts() {
  local n
  # Match the path PREFIX, not up to a closing quote: an implementation that appends a query
  # string still posted the artifact, and counting it as absent would blame the wrong assertion —
  # a token-in-the-URL mutant came back as "shipped nothing" while the log plainly showed all
  # four kinds arriving.
  n="$(grep -c "\"p\": *\"[^\"]*/artifacts/$1[\"?]" "$T/coord.log" 2>/dev/null)" || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# artauth <kind> — the distinct Authorization values seen on ARTIFACT posts of one kind.
# Scoped deliberately: the status channel already sends a bearer header, so a check that greps
# the whole log passes without a single artifact ever being posted.
artauth() {
  python3 -c "
import json,sys
seen=[]
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if '/artifacts/'+sys.argv[2] in r.get('p','').split('?')[0]:
        a=r.get('auth','')
        if a not in seen: seen.append(a)
for a in seen: print(a)
" "$T/coord.log" "$1" 2>/dev/null
}

# artpaths <kind> — the request paths for one kind, one per line.
artpaths() {
  python3 -c "
import json,sys,re
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if '/artifacts/'+sys.argv[2] in r.get('p','').split('?')[0]: print(r['p'])
" "$T/coord.log" "$1" 2>/dev/null
}

# artbody <kind> [index] — the received BYTES of the nth artifact of a kind (default the largest).
artbody() {
  python3 -c "
import json,sys
rows=[]
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if '/artifacts/'+sys.argv[2] in r.get('p','').split('?')[0]: rows.append(r)
if not rows: sys.exit(1)
r = rows[int(sys.argv[3])] if len(sys.argv)>3 and sys.argv[3]!='max' else max(rows,key=lambda x:x['n'])
sys.stdout.write(open(r['f'],'rb').read().decode('utf-8','replace'))
" "$T/coord.log" "$1" "${2:-max}" 2>/dev/null
}

# artsize <kind> — the byte count of the largest received artifact of a kind.
artsize() {
  python3 -c "
import json,sys
best=0
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if '/artifacts/'+sys.argv[2] in r.get('p','').split('?')[0]: best=max(best,r['n'])
print(best)
" "$T/coord.log" "$1" 2>/dev/null || echo 0
}

# --- executors that produce the states these gates must tell apart ---------------------------
# The worker-channel executor always succeeds silently, which produces neither a .diff (written
# only when an attempt FAILS) nor a non-empty .log. A gate written against it alone would assert
# nothing about either, and both are artifacts this spec exists to ship.

# mkexec_loud — succeeds, and writes enough to stdout that the transcript is not empty.
mkexec_loud() {
  cat > "$T/exec.sh" <<'X'
#!/usr/bin/env bash
echo "invoked" >> "$ROOT/execlog.txt"
for i in $(seq 1 40); do echo "executor line $i: considering the task"; done
if   [ ! -f "$ROOT/a.txt" ]; then echo a > "$ROOT/a.txt"
elif [ ! -f "$ROOT/b.txt" ]; then echo b > "$ROOT/b.txt"; fi
X
  chmod +x "$T/exec.sh"
}

# mkexec_fail — writes a file the gate does not accept, so every attempt fails and log_failure
# runs. It must CHANGE something: a no-op is caught earlier as "changed nothing" and never
# reaches the gate, so an executor that does nothing would test a different path than intended.
mkexec_fail() {
  cat > "$T/exec.sh" <<'X'
#!/usr/bin/env bash
echo "invoked" >> "$ROOT/execlog.txt"
echo "working on it" 
date +%s%N > "$ROOT/wrong.txt"
X
  chmod +x "$T/exec.sh"
}

# mkexec_big <kib> — succeeds, having created an untracked file of the requested size. The diff
# writer inlines untracked file CONTENTS, so this is what makes an artifact exceed a cap.
mkexec_big() {
  local kib="${1:-256}"
  cat > "$T/exec.sh" <<X
#!/usr/bin/env bash
echo "invoked" >> "\$ROOT/execlog.txt"
head -c $((kib * 1024)) /dev/zero | tr '\\0' 'x' > "\$ROOT/big.txt"
if   [ ! -f "\$ROOT/a.txt" ]; then echo a > "\$ROOT/a.txt"
elif [ ! -f "\$ROOT/b.txt" ]; then echo b > "\$ROOT/b.txt"; fi
X
  chmod +x "$T/exec.sh"
}

# mkloop_logged <dir> — mkloop, plus the .gitignore that keeps the evidence tree alive.
#
# mkloop's repo has no .gitignore, so `.evidence/` is untracked and the loop's between-attempt
# `git clean -fd` deletes it. Every artifact write then fails, the executor's transcript cannot be
# created, and the loop reads "0B of output" as `the executor did not start` and ABORTS — so a
# fixture without this produces no evidence at all on exactly the failing-attempt path this spec
# most needs to observe. The real repo is protected by its own .gitignore; `git clean -fdx` would
# reproduce it there too. Recorded in evidence/2026-08-28-clean-eats-the-evidence-dir.md.
mkloop_logged() {
  mkloop "$1"
  printf '.evidence/\n' > "$1/.gitignore"
  ( cd "$1" && git add -A && git commit -qm gitignore ) >/dev/null 2>&1
}

# mkexec_loud_big <kib> — succeeds, having written roughly <kib> KiB to stdout. The transcript is
# the largest artifact a run produces and the one most likely to exceed any cap, so the cap's
# behaviour has to be observable on it and not only on a diff.
mkexec_loud_big() {
  local kib="${1:-256}"
  cat > "$T/exec.sh" <<X
#!/usr/bin/env bash
echo "invoked" >> "\$ROOT/execlog.txt"
head -c $((kib * 1024)) /dev/zero | tr '\\0' 'y' | fold -w 120
if   [ ! -f "\$ROOT/a.txt" ]; then echo a > "\$ROOT/a.txt"
elif [ ! -f "\$ROOT/b.txt" ]; then echo b > "\$ROOT/b.txt"; fi
X
  chmod +x "$T/exec.sh"
}

# diskfile <dir> <glob> — the largest matching artifact the run wrote, for comparing what was
# SHIPPED against what was WRITTEN. A gate that only inspects what arrived cannot tell a correctly
# truncated artifact from one the implementation never had in full.
diskfile() { find "$1/.evidence/runs" -name "$2" -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-; }

# allpaths — every request path the coordinator recorded, whatever the kind. The leak assertion
# needs all of them: a token smuggled into a query string is a leak wherever it lands.
allpaths() { python3 -c "
import json,sys
for ln in open(sys.argv[1]):
    try: print(json.loads(ln).get('p',''))
    except Exception: pass
" "$T/coord.log" 2>/dev/null; }
