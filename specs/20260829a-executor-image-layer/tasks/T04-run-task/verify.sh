#!/usr/bin/env bash
# T4 — one run-task.sh, in this repo, routed through run-loop.sh.
#
# Offline by construction. The fixture pre-creates the workspace clone with a LOCAL bare origin,
# so `git fetch origin` succeeds without network and the clone branch is not taken; the clone
# path itself is asserted on the script's instruction lines, never on its comments.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

RT="$ROOT/scripts/run-task.sh"
if [ ! -f "$RT" ]; then
  for i in 1 2 3 4 5 6 7 8 9; do
    no "ac$i: scripts/run-task.sh does not exist — the single remote entry point is the task"
  done
  gate_done
fi
nonempty_strip "$RT" || { no "ac0: run-task.sh has no instruction lines — every scoped check below would pass for free"; gate_done; }

# ── the offline fixture: a bare origin, a clone, a baked harness ─────────────────────────────
WS="$T/ws"; mkdir -p "$WS"
git init -q --bare "$T/origin.git"
mkrepo "$T/seed"; mkspec "$T/seed" fx
git -C "$T/seed" checkout -q main 2>/dev/null || git -C "$T/seed" checkout -q -b main
git -C "$T/seed" add -A && git -C "$T/seed" commit -qm specs --allow-empty
git -C "$T/seed" remote add origin "$T/origin.git" && git -C "$T/seed" push -q origin main
git clone -q "$T/origin.git" "$WS/proj"

# A baked harness: a plain directory, NOT a git checkout, carrying a stub run-loop.sh.
BAKED="$T/harness-baked"; mkdir -p "$BAKED/scripts"
cat > "$BAKED/scripts/run-loop.sh" <<'STUB'
#!/usr/bin/env bash
echo "RUNLOOP-CALLED strategy=$1 spec=$2 cwd=$(basename "$PWD")"
STUB
chmod +x "$BAKED/scripts/run-loop.sh"
cp "$BAKED/scripts/run-loop.sh" "$BAKED/scripts/ralph-build.sh"

# Both names carry the SAME sentinel value on purpose: the clone credential was renamed
# HARNESS_GITHUB_PAT -> HARNESS_CLONE_PAT by 20260830a (docs/executors.md), and one sentinel value
# means the leak grep below covers either name without becoming two checks that can disagree.
run_rt() { ( cd "$T" && HARNESS_WORKSPACE="$WS" HARNESS_DIR="$BAKED" HARNESS_REPO_NAME=proj \
               HARNESS_GITHUB_PAT=SENTINEL-PAT-4c1f HARNESS_CLONE_PAT=SENTINEL-PAT-4c1f \
               bounded 30 bash "$RT" "$@" ) 2>&1; }

# ── ac1: flags work in any position ──────────────────────────────────────────────────────────
a="$(run_rt specs/fx --repo proj --strategy build-converge)"
b="$(run_rt --strategy build-converge --repo proj specs/fx)"
if echo "$a" | grep -qi 'usage:'; then
  no "ac1: run-task.sh rejected its own documented form 'specs/fx --repo proj --strategy X'"
elif echo "$b" | grep -qi 'usage:'; then
  no "ac1: flags before the positional were rejected. The three copies drifted on positional order badly enough that one had to make --repo a flag 'so deploy order stops mattering'; order-dependence is the defect being removed"
elif ! echo "$a" | grep -q 'RUNLOOP-CALLED' || ! echo "$b" | grep -q 'RUNLOOP-CALLED'; then
  no "ac1: one of the two orderings never reached the loop. a=[$(echo "$a" | tail -1)] b=[$(echo "$b" | tail -1)]"
else
  ok "ac1: <spec-dir> is positional and the flags work in any position"
fi

# ── ac2: a bad --repo is REJECTED, never sanitised ───────────────────────────────────────────
before="$(ls -A "$WS" | sort | tr '\n' ' ')"
out="$( cd "$T" && HARNESS_WORKSPACE="$WS" HARNESS_DIR="$BAKED" \
          bounded 30 bash "$RT" specs/fx --repo '../../etc' 2>&1 )"; rc=$?
after="$(ls -A "$WS" | sort | tr '\n' ' ')"
if [ "$rc" = 0 ]; then
  no "ac2: a --repo of '../../etc' was accepted. The value becomes a path AND a URL; a name that needs escaping is a name to refuse"
elif echo "$out" | grep -q 'RUNLOOP-CALLED'; then
  no "ac2: the run proceeded after a bad --repo"
elif [ "$before" != "$after" ]; then
  no "ac2: the workspace changed while rejecting a bad --repo (before=[$before] after=[$after]) — rejection must happen before anything is created"
elif echo "$out" | grep -qiE 'sanitis|sanitiz|stripped|cleaned'; then
  no "ac2: the message says the value was sanitised. Reject, never sanitise — a sanitiser turns an attack into a surprising path"
else
  ok "ac2: a --repo needing escaping is rejected before anything is created"
fi

# ── ac3: no credential in the URL or in argv ─────────────────────────────────────────────────
out="$(run_rt specs/fx --repo proj)"
if echo "$out" | grep -q 'SENTINEL-PAT-4c1f'; then
  no "ac3: the PAT appeared in run-task.sh's own output. The transcript now ships to the coordinator, so a token here leaves the machine"
elif instr "$RT" 'https://[^ ]*(x-access-token|\$\{?HARNESS_(GITHUB|CLONE)_PAT)'; then
  no "ac3: run-task.sh builds a clone URL containing a credential. entrypoint.sh already wrote ~/.git-credentials; a token in the URL lands in process listings and in the log"
elif ! instr "$RT" 'git[[:space:]]+clone'; then
  no "ac3: run-task.sh no longer clones at all — the on-demand clone is what lets an agent be handed work in a repo it has not seen"
else
  ok "ac3: the clone carries no credential in its URL or argv"
fi

# ── ac4: the same spec can be run twice in one container ─────────────────────────────────────
# The trap: `rm -rf` alone leaves the worktree REGISTERED in .git/worktrees, so the second `add`
# fails with "missing but already registered". That made a spec runnable exactly once, and
# re-running a spec after editing it is the normal SDD loop.
first="$(run_rt specs/fx --repo proj)"
second="$(run_rt specs/fx --repo proj)"
if ! echo "$first" | grep -q 'RUNLOOP-CALLED'; then
  no "ac4: the FIRST run never reached the loop, so the second proves nothing. Output: $(echo "$first" | tail -2 | tr '\n' ' ')"
elif echo "$second" | grep -qi 'already registered\|already exists\|missing but'; then
  no "ac4: the second run of the same spec failed on a registered worktree — `git worktree prune` is missing, or runs after `add` instead of before"
elif ! echo "$second" | grep -q 'RUNLOOP-CALLED'; then
  no "ac4: the second run of the same spec did not reach the loop. Output: $(echo "$second" | tail -2 | tr '\n' ' ')"
else
  ok "ac4: the same spec runs twice — remove --force and prune both precede add"
fi

# ── ac5: a present-but-not-a-checkout workspace is refused, never deleted ────────────────────
mkdir -p "$WS/notrepo"; echo "someone else's data" > "$WS/notrepo/PRECIOUS"
out="$( cd "$T" && HARNESS_WORKSPACE="$WS" HARNESS_DIR="$BAKED" \
          bounded 30 bash "$RT" specs/fx --repo notrepo 2>&1 )"; rc=$?
if [ ! -f "$WS/notrepo/PRECIOUS" ]; then
  no "ac5: run-task.sh DELETED a non-checkout to make room. Deleting it is the worst possible recovery — something else lives there"
elif [ "$rc" = 0 ]; then
  no "ac5: run-task.sh continued past a workspace path that is not a git checkout"
else
  ok "ac5: a present-but-not-a-checkout path is refused and left intact"
fi

# ── ac6: the loop is reached through run-loop.sh, with a strategy ────────────────────────────
out="$(run_rt specs/fx --repo proj --strategy build-then-judge)"
if ! echo "$out" | grep -q 'RUNLOOP-CALLED'; then
  no "ac6: run-loop.sh was never invoked. Calling ralph-build.sh directly is why the remote path has no strategies, no phases and no judge, and why STRATEGY on a dispatched Job has nowhere to land"
elif ! echo "$out" | grep -q 'strategy=build-then-judge'; then
  no "ac6: the requested strategy did not reach run-loop.sh. Saw: $(echo "$out" | grep RUNLOOP-CALLED | head -1)"
else
  ok "ac6: run-task.sh invokes run-loop.sh with the requested strategy"
fi
out="$(run_rt specs/fx --repo proj)"
echo "$out" | grep -q 'strategy=build-converge' \
  && ok "ac6b: the default strategy is build-converge" \
  || no "ac6b: the default strategy is not build-converge. Saw: $(echo "$out" | grep RUNLOOP-CALLED | head -1)"

# ── ac7: a BAKED harness dir is used as-is — no clone, no fetch ──────────────────────────────
# $BAKED is a plain directory with no .git. If run-task.sh clones over it, the fleet image loses
# the one property baking exists to provide: that the image tag IS the harness version.
marker="$BAKED/scripts/MARKER"; : > "$marker"
out="$(run_rt specs/fx --repo proj)"
if [ ! -f "$marker" ]; then
  no "ac7: the baked harness directory was replaced — run-task.sh cloned over a non-git \$HARNESS_DIR. Two runs of one image would then behave differently, and the evidence corpus could not attribute a regression"
elif [ -d "$BAKED/.git" ]; then
  no "ac7: run-task.sh turned the baked harness into a git checkout"
elif ! echo "$out" | grep -q 'RUNLOOP-CALLED'; then
  no "ac7: with a baked harness, the loop was never reached. Output: $(echo "$out" | tail -2 | tr '\n' ' ')"
else
  ok "ac7: a non-git \$HARNESS_DIR is used as-is, with no clone and no fetch"
fi

# ── ac8: a git harness dir is fast-forwarded, and a failed fetch is survivable ───────────────
# POSITIVE CONTROL for ac7: the same probe must read DIFFERENTLY when the dir IS a checkout.
GH="$T/harness-git"; mkrepo "$GH"; mkdir -p "$GH/scripts"
cp "$BAKED/scripts/run-loop.sh" "$GH/scripts/run-loop.sh"
git -C "$GH" add -A && git -C "$GH" commit -qm h
git -C "$GH" remote add origin "$T/nonexistent-remote.git"   # fetch WILL fail
out="$( cd "$T" && HARNESS_WORKSPACE="$WS" HARNESS_DIR="$GH" HARNESS_REPO_NAME=proj \
          bounded 30 bash "$RT" specs/fx --repo proj 2>&1 )"
if ! echo "$out" | grep -q 'RUNLOOP-CALLED'; then
  no "ac8: a git \$HARNESS_DIR whose fetch fails stopped the run. A network blip must run the loop you already have, not refuse to work. Output: $(echo "$out" | tail -2 | tr '\n' ' ')"
elif ! echo "$out" | grep -qiE 'fetch|fast-forward|as-is|as is'; then
  no "ac8: the failed fetch was silent. 'Using the checkout as-is' and 'fast-forwarded to origin' are two states a reader must be able to tell apart when a run behaves oddly"
else
  ok "ac8: a git \$HARNESS_DIR is fast-forwarded and survives a failed fetch"
fi

# ── ac9: the push and PR commands are PRINTED, not run ───────────────────────────────────────
out="$(run_rt specs/fx --repo proj)"
pushed="$(git -C "$T/origin.git" for-each-ref --format='%(refname)' | grep -c 'ralph/' || true)"
if [ "$pushed" != "0" ]; then
  no "ac9: run-task.sh PUSHED a branch to origin. Code egress is its own spec — bot identity, PR body, and what happens when the gate is red are decisions this task does not get to make"
elif ! echo "$out" | grep -q 'git push'; then
  no "ac9: the success path no longer prints the push command, so a human watching the run has nothing to copy"
elif ! echo "$out" | grep -qE 'gh pr|pull request'; then
  no "ac9: the success path does not print how to open the PR"
else
  ok "ac9: the push and PR commands are printed and not run"
fi

gate_done
