#!/usr/bin/env bash
# Smoke the harness images: can they RUN, not merely do they layer correctly.
#
# Every assertion in 20260829a T01's gate reads Dockerfile TEXT, and a Dockerfile that layers
# correctly is indistinguishable from an image that can actually run a task when all you have is
# the text. This script is what tells them apart, which is why it is not a loop gate: a gate that
# shells out to `docker build` is neither deterministic nor offline.
#
# It lives here, as a CLI, rather than inline in the workflow, because two callers need it and a
# copy in each would drift:
#   - `pr-verify`, against images built from the PR and never pushed  (the checkpoint)
#   - `smoke`, against the tags main just published and pulled back   (the canary)
# Being a CLI also means a human can run it on a laptop against local tags, which is how the
# worktree and SIGPIPE defects below were actually found.
#
#   usage: smoke-images.sh <base-ref> <derived-ref>
set -euo pipefail

BASE="${1:?usage: smoke-images.sh <base-ref> <derived-ref>}"
DERIVED="${2:?usage: smoke-images.sh <base-ref> <derived-ref>}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── base:    $BASE"
echo "── derived: $DERIVED"

# ── the base carries the loop, its runtime, and NO model CLI ─────────────────────────────────
echo "── the base carries the loop, its runtime, and NO model CLI"
docker run --rm --entrypoint bash "$BASE" -c '
  set -euo pipefail
  for t in bash git jq python3 run-task.sh run-loop.sh ralph-build.sh; do
    command -v "$t" >/dev/null || { echo "FAIL: $t is not on PATH in harness-base"; exit 1; }
  done
  [ -r "$HARNESS_HOME/specs/lib/assert.sh" ] || { echo "FAIL: assert.sh missing"; exit 1; }

  # Captured, not piped: `... | grep -q` makes grep exit at the first match and the producer take
  # SIGPIPE, and pipefail then fails the pipeline on a SUCCESSFUL match. Small outputs usually win
  # the race, which is worse than losing it — it fails once in a while, for no visible reason.
  builtins="$(run-loop.sh --list)"
  case "$builtins" in
    *build-converge*) ;;
    *) echo "FAIL: --list resolves no built-ins"; exit 1 ;;
  esac

  rc=0
  for c in opencode codex claude; do
    command -v "$c" >/dev/null 2>&1 && { echo "FAIL: $c is installed in harness-base"; rc=1; }
  done
  [ "$rc" = 0 ] || exit 1
  echo "base OK: loop + runtime present, no model CLI"
'

# ── the entrypoint is run-task.sh and it fails closed ────────────────────────────────────────
echo "── the entrypoint is run-task.sh and it fails closed"
set +e
out="$(docker run --rm "$BASE" 2>&1)"; rc=$?
set -e
echo "$out"
[ "$rc" != 0 ] || { echo "FAIL: entrypoint exited 0 with no spec-dir"; exit 1; }
case "$out" in
  *[Uu]sage*) ;;
  *) echo "FAIL: entrypoint printed no usage"; exit 1 ;;
esac

# ── the derived image declares its binding ───────────────────────────────────────────────────
echo "── the derived image declares its binding"
docker run --rm --entrypoint bash "$DERIVED" -c '
  set -euo pipefail
  command -v opencode    >/dev/null || { echo "FAIL: the declared binding (opencode) is absent"; exit 1; }
  command -v run-loop.sh >/dev/null || { echo "FAIL: the derived image lost the loop"; exit 1; }
  echo "derived OK: opencode present, loop intact"
'

# ── the actual task ──────────────────────────────────────────────────────────────────────────
# A stub executor stands in for the model — there is no provider credential here, and the point
# is the LOOP, not the model: does run-task.sh clone, cut a worktree, route through run-loop.sh,
# reach a green gate, commit, and leave an attempt record behind. STRATEGY_TOOLS="opencode" is
# still preflighted against the real image, so "the declared binding is absent" remains a genuine
# failure mode of this step.
echo "── build the fixture repo"
cd "$WORK"
mkdir -p ws && git init -q --bare ws/origin.git
git init -q seed && cd seed
git config user.email smoke@ci && git config user.name smoke
mkdir -p specs/fx/tasks/T01-a
printf '# fx\n\n- **Tools:** none\n- **MCP:** none\n' > specs/fx/spec.md
printf 'T1: create a.txt containing the letter a.\n'  > specs/fx/tasks.txt
printf '#!/usr/bin/env bash\n[ -f a.txt ] && { echo "  PASS  ac1"; echo "VERIFY: PASS"; exit 0; }\necho "  FAIL  ac1" >&2; echo "VERIFY: FAIL"; exit 1\n' > specs/fx/verify.sh
cp specs/fx/verify.sh specs/fx/tasks/T01-a/verify.sh
chmod +x specs/fx/verify.sh specs/fx/tasks/T01-a/verify.sh
git add -A && git commit -qm fixture
git branch -M main && git remote add origin ../ws/origin.git && git push -q origin main
cd .. && git clone -q ws/origin.git ws/fx
printf '#!/usr/bin/env bash\necho a > "${ROOT:?}/a.txt"\necho "stub executor wrote a.txt"\n' > ws/stub-exec.sh
chmod +x ws/stub-exec.sh

echo "── run a fixture task through run-task.sh in the derived image"
docker run --rm \
  -v "$PWD/ws:/ws" -w /ws \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e HARNESS_WORKSPACE=/ws \
  -e HARNESS_DIR=/harness \
  -e RALPH_EXEC_CMD=/ws/stub-exec.sh \
  -e RALPH_AGENT=smoke \
  -e RALPH_SHEET=off \
  -e GIT_AUTHOR_NAME=smoke -e GIT_AUTHOR_EMAIL=smoke@ci \
  -e GIT_COMMITTER_NAME=smoke -e GIT_COMMITTER_EMAIL=smoke@ci \
  --entrypoint run-task.sh \
  "$DERIVED" \
  specs/fx --repo fx --strategy build-converge

# ── a commit was produced and an attempt record was written ──────────────────────────────────
# Read from INSIDE the container, on the same mount. run-task.sh cuts a git worktree, whose .git
# is a FILE holding an absolute `gitdir:` pointer — /ws/fx/.git/worktrees/fx-fx, a path that
# exists only in the container. From outside, the directory is there but the gitlink dangles, so
# `[ -d ]` passes and every git command then fails "not a git repository".
echo "── a commit was produced and an attempt record was written"
docker run --rm \
  -v "$PWD/ws:/ws" -w /ws \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  --entrypoint bash \
  "$DERIVED" -c '
    set -euo pipefail
    WT=/ws/fx-fx
    [ -d "$WT" ] || { echo "FAIL: run-task.sh cut no worktree at $WT"; exit 1; }

    log="$(git -C "$WT" log --oneline)"
    printf "%s\n" "$log" | sed -n "1,5p"
    case "$log" in
      *"ralph(smoke)"*) ;;
      *) echo "FAIL: no commit was produced — the loop reached no green gate"; exit 1 ;;
    esac

    [ -f "$WT/a.txt" ] || { echo "FAIL: the task artifact is absent from the worktree"; exit 1; }

    # Guarded, not 2>/dev/null: find on a missing directory exits 1, the assignment fails under
    # pipefail, and set -e aborts BEFORE the message below — a gate that fails without saying why.
    if [ -d "$WT/.evidence" ]; then
      n="$(find "$WT/.evidence" -name "*.json" | wc -l)"
    else
      n=0
    fi
    [ "$n" -gt 0 ] || { echo "FAIL: no attempt record was written — the run left nothing to diagnose with"; exit 1; }

    echo "smoke OK: commit produced, artifact present, $n attempt record(s) written"
  '
