#!/usr/bin/env bash
# exec-codex.sh — the Codex executor binding for the build loop.
#
# Same contract as exec-qwen.sh: prompt in $1, ROOT from the environment, transcript on stdout.
# This file plus scripts/loops/build-codex.conf is the ENTIRE cost of adding an executor — it
# replaced a 204-line copy of the whole loop, which three specs then had to police for drift.
#
# --skip-git-repo-check: the loop already guarantees a git worktree on a throwaway branch.
# Sandboxing is left to the container, which is the real boundary here; CODEX_SANDBOX overrides
# it for a laptop run, where there is no outer sandbox.
#
# -c projects."$R".trust_level: trust the worktree we were actually handed, rather than hoping
# it appears in a list somebody wrote earlier. The container's codex-config.toml pre-trusts one
# path (/Users/mtgibbs/dev/pi-cluster) — which could never have covered dispatch: run-task.sh
# --repo clones ANY repo and every spec gets a fresh SIBLING worktree
# (/Users/mtgibbs/dev/<repo>-<spec>), so the set of paths needing trust is unbounded and unknown
# until a task starts. A static list looks like coverage and misses every real run.
#
# Nothing gates on trust today — sandbox_mode is danger-full-access and an exec in an untrusted
# sibling was verified not to stall (2026-08-27, coding-harness-codex, cwd notes-from-hearing).
# This is for the version that starts enforcing it, and unlike a path list it will still be
# right then. The override was confirmed to parse and run before it was committed.
set -uo pipefail
R="${ROOT:-$PWD}"
exec codex exec --cd "$R" \
  --sandbox "${CODEX_SANDBOX:-danger-full-access}" \
  -c "projects.\"$R\".trust_level=\"trusted\"" \
  --skip-git-repo-check "${1:?exec-codex.sh <prompt>}"
