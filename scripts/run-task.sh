#!/usr/bin/env bash
# run-task.sh <spec-dir> [--repo NAME] [--branch NAME] [--base NAME] [--strategy NAME]
#
# THE single remote entry point. A dispatched Job, a tmux send-keys, and a human at a shell all
# arrive here, and this is the one copy: beelink-ansible carried three under
# files/coding-harness-{qwen,claude,codex}/ that had already drifted on positional order badly
# enough that one of them made --repo a flag "so deploy order stops mattering". That drift is
# what this file removes — <spec-dir> is positional, everything else is a flag in any position.
#
# It sets up a worktree as a SIBLING of the repo clone (the constitution's manual
# `git worktree add ../<repo>-<task>` pattern) and hands it to run-loop.sh with a STRATEGY.
# Not ralph-build.sh directly: calling the loop script directly is why the remote path has no
# strategies, no phases and no judge today, and why STRATEGY on a dispatched Job had nowhere to
# land. The per-executor env the codex copy set — RALPH_AGENT, RALPH_SHEET, the exec binding —
# is exactly what build-codex.conf already declares, so routing through a strategy DELETES that
# difference rather than porting it. None of it appears below, deliberately.
#
# Code egress is a separate spec: on success the push and PR-open commands are PRINTED and never
# run.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: run-task.sh <spec-dir> [--repo NAME] [--branch NAME] [--base NAME] [--strategy NAME]

  <spec-dir>    positional, relative to the worked repo (e.g. specs/my-feature)
  --repo NAME   repository under $HARNESS_WORKSPACE to work in
  --branch NAME branch to create (default: ralph/<spec>-<epoch>)
  --base NAME   branch to cut from (default: main) — a spec authored on spec/<feature>
                by another session is invisible to a worktree cut from origin/main
  --strategy NAME  loop strategy (default: build-converge)
USAGE
}

SPEC_DIR=""
REPO_NAME="${HARNESS_REPO_NAME:-}"
BRANCH=""
BASE_BRANCH="main"
STRATEGY="build-converge"

# Flags in ANY position, <spec-dir> positional. The three copies drifted on positional order;
# order-dependence is the defect being removed, so this loop never cares where a flag lands.
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO_NAME="${2:?run-task: --repo needs a value}";     shift 2 ;;
    --branch)   BRANCH="${2:?run-task: --branch needs a value}";      shift 2 ;;
    --base)     BASE_BRANCH="${2:?run-task: --base needs a value}";   shift 2 ;;
    --strategy) STRATEGY="${2:?run-task: --strategy needs a value}";  shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    --*)        echo "run-task: unknown flag '$1'" >&2; usage; exit 64 ;;
    *)
      if [ -z "$SPEC_DIR" ]; then SPEC_DIR="$1"; shift
      else echo "run-task: unexpected second positional '$1'" >&2; usage; exit 64; fi ;;
  esac
done

[ -n "$SPEC_DIR" ]   || { echo "run-task: <spec-dir> is required" >&2; usage; exit 64; }
[ -n "$REPO_NAME" ]  || { echo "run-task: --repo (or \$HARNESS_REPO_NAME) is required" >&2; usage; exit 64; }

# REJECT, never sanitise, and do it BEFORE anything is created. The value becomes both a path
# component and a URL component; a name that needs escaping is a name to refuse, because a
# sanitiser turns an attack into a surprising path that still resolves somewhere.
case "$REPO_NAME" in
  *[!A-Za-z0-9._-]*)
    echo "run-task: --repo '$REPO_NAME' contains a character outside [A-Za-z0-9._-] — refusing." >&2
    echo "run-task: the value becomes both a path and a URL. It is not altered to make it fit." >&2
    exit 65 ;;
esac

WORKSPACE="${HARNESS_WORKSPACE:-/home/agent/workspace}"
BASE="$WORKSPACE/$REPO_NAME"
TASK_DIR="$WORKSPACE/${REPO_NAME}-$(basename "$SPEC_DIR")"
BRANCH="${BRANCH:-ralph/$(basename "$SPEC_DIR")-$(date +%s 2>/dev/null || echo run)}"

# ── the harness itself: baked or cloned ──────────────────────────────────────────────────────
# A directory that is NOT a git checkout is the FLEET IMAGE, where the harness is baked at the
# image's own version. Cloning over it would mean two runs of one image could behave
# differently, which destroys the only property baking exists to provide. A directory that IS a
# checkout is a developer box, and gets fast-forwarded — but a failed fetch runs the loop you
# already have rather than refusing to work, because a network blip is not a reason to stop.
# Which of the two happened is stated out loud: they are states a reader must be able to tell
# apart when a run behaves oddly.
HARNESS_DIR="${HARNESS_DIR:-/harness}"
HARNESS_REF="${HARNESS_REF:-main}"
[ -d "$HARNESS_DIR" ] || { echo "run-task: \$HARNESS_DIR '$HARNESS_DIR' does not exist" >&2; exit 66; }

if git -C "$HARNESS_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$HARNESS_DIR" fetch --quiet origin "$HARNESS_REF" 2>/dev/null \
     && git -C "$HARNESS_DIR" merge --ff-only --quiet FETCH_HEAD 2>/dev/null; then
    echo "run-task: harness checkout fast-forwarded to origin/$HARNESS_REF"
  else
    echo "run-task: harness fetch failed — continuing with the checkout as-is"
  fi
else
  echo "run-task: harness is baked (not a checkout) — used as-is, no clone and no fetch"
fi

RUN_LOOP="$HARNESS_DIR/scripts/run-loop.sh"
[ -f "$RUN_LOOP" ] || { echo "run-task: $RUN_LOOP not found" >&2; exit 66; }

# ── the worked repo: cloned on demand, never over something else ─────────────────────────────
# A path that exists but is not a checkout is REFUSED and left alone. Deleting it is the worst
# possible recovery: something else lives there, and this script does not know what.
if [ -e "$BASE" ] && ! git -C "$BASE" rev-parse --git-dir >/dev/null 2>&1; then
  echo "run-task: '$BASE' exists but is not a git checkout — refusing, and leaving it untouched." >&2
  exit 67
fi

if [ ! -e "$BASE" ]; then
  # A plain https URL with NO token in it. entrypoint.sh already wrote ~/.git-credentials from
  # HARNESS_CLONE_PAT (docs/executors.md), so the helper supplies the secret; a token here would
  # land in argv, in process listings, and in the transcript that now ships to the coordinator.
  # HARNESS_CLONE_PAT, not HARNESS_OUTCOME_PAT: cloning is the read identity.
  REPO_URL="${HARNESS_REPO_URL:-https://github.com/${HARNESS_GITHUB_OWNER:-mtgibbs}/$REPO_NAME.git}"
  echo "run-task: cloning $REPO_URL"
  mkdir -p "$WORKSPACE"
  git clone "$REPO_URL" "$BASE"
fi

git -C "$BASE" fetch origin || echo "run-task: fetch of '$REPO_NAME' failed — using the refs already here"

# remove --force AND prune, both BEFORE add. `rm -rf` alone leaves the worktree REGISTERED in
# .git/worktrees, so the second `add` dies with "missing but already registered" — that made a
# spec runnable exactly once per container, and re-running a spec after editing it is the normal
# SDD loop. -B rather than -b for the same reason: the second run of one spec inside one second
# would otherwise collide on the branch name it just created.
git -C "$BASE" worktree remove --force "$TASK_DIR" 2>/dev/null || true
git -C "$BASE" worktree prune
git -C "$BASE" worktree add -B "$BRANCH" "$TASK_DIR" "origin/$BASE_BRANCH"

cd "$TASK_DIR"
echo "════════ run-task: $SPEC_DIR on $BRANCH ($REPO_NAME, strategy $STRATEGY) ════════"

if bash "$RUN_LOOP" "$STRATEGY" "$SPEC_DIR"; then
  echo "════════ run-task: DONE — review, then push and open the PR yourself ════════"
  echo "  cd $TASK_DIR && git push -u origin $BRANCH"
  echo "  gh pr create --base $BASE_BRANCH --head $BRANCH"
else
  rc=$?
  echo "════════ run-task: STOPPED (exit $rc) — needs a human, see the output above ════════" >&2
  exit "$rc"
fi
