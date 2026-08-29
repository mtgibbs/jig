#!/usr/bin/env bash
# Convergence gate for 20260829a — the end state, after all six tasks.
#
# run-loop.sh REQUIRES this file to exist (it refuses a spec dir without spec.md + verify.sh), and
# 20260827c-last-task-strict runs it with STRICT=1 on the final task. The spec merged in #55
# without it and was therefore unrunnable: `run-loop: specs/20260829a-executor-image-layer needs
# spec.md + verify.sh`, exit 1, before a single task started.
#
# It asserts only what NO per-task gate can. Each assertion below is a GLOBAL property — true of
# the repository as a whole rather than of one artifact — because a convergence gate that restates
# a task gate is worse than absent: it passes in the cases the real gate would catch and reads as
# independent confirmation. Criteria are taken from spec.md §2 Outcomes, not invented here.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

gate_tmpdir
trap 'rm -rf "$T"' EXIT

# end-1 — Outcome 2, the half T04 cannot see. T04 checks the run-task.sh it FINDS; only a
# repo-wide count can say there is exactly one. The whole point is reconciling three copies that
# live in beelink-ansible, and a reconciliation that leaves a second copy behind in this repo has
# recreated the fork this spec exists to remove.
n_rt="$(find "$ROOT" -name 'run-task.sh' -not -path '*/.git/*' -not -path '*/.evidence/*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n_rt" = 0 ]; then
  no "end-1: no run-task.sh anywhere in the repo — Outcome 2 wants exactly one, in this repo"
elif [ "$n_rt" != 1 ]; then
  no "end-1: $n_rt copies of run-task.sh exist: $(find "$ROOT" -name 'run-task.sh' -not -path '*/.git/*' -not -path '*/.evidence/*' 2>/dev/null | sed "s|$ROOT/||" | tr '\n' ' ')— one entry point means one file, not one per caller"
else
  ok "end-1: exactly one run-task.sh exists in the repo"
fi

# end-2 — Outcome 1, stated over ALL Dockerfiles rather than the two T01 names. A third image
# added later that bakes a CLI into the base re-inverts the layering without touching either file
# T01 asserts on, and nothing would notice.
base="$ROOT/docker/harness-base.Dockerfile"
if [ ! -f "$base" ]; then
  no "end-2: docker/harness-base.Dockerfile does not exist, so the loop has no model-free image to ship"
elif ! nonempty_strip "$base"; then
  no "end-2: harness-base.Dockerfile has no instruction lines — every absence check below would pass for free"
elif instr "$base" '(opencode|@anthropic-ai/claude-code|gemini|codex)'; then
  no "end-2: the base image installs a model CLI, so it is an executor image and 'FROM harness-base' is not the whole cost of a new executor"
else
  offenders=""
  for df in "$ROOT"/docker/*.Dockerfile; do
    case "$(basename "$df")" in harness-base.Dockerfile) continue ;; esac
    nonempty_strip "$df" || continue
    instr "$df" '^FROM .*harness-base' || offenders="$offenders $(basename "$df")"
  done
  if [ -n "$offenders" ]; then
    no "end-2: executor image(s) not built on the base:$offenders — each one is a fork of the loop again, which is what this spec removes"
  else
    ok "end-2: the base carries no model CLI and every executor image derives from it"
  fi
fi

# end-3 — Outcome 6, the regression guard, and the only assertion here that RUNS anything. Every
# other task in this spec widens a path the laptop already uses; the way that goes wrong is not a
# failing assertion but an ordinary invocation that no longer works. Bounded, because a resolver
# that picks the wrong strategy calls a real executor and waits (see fixtures.sh `bounded`).
mkrepo "$T/plain" >/dev/null 2>&1
mkspec "$T/plain" fx
out="$( cd "$T/plain" && bounded 30 bash "$ROOT/scripts/run-loop.sh" --list 2>&1 )"; rc=$?
if [ "$rc" = 124 ] || [ "$rc" = 142 ]; then
  no "end-3: 'run-loop.sh --list' did not finish inside 30s. A hang is not a failure and must not be read as one"
elif [ "$rc" != 0 ]; then
  no "end-3: 'run-loop.sh --list' exited $rc from an ordinary repo. Outcome 6 is that a laptop run behaves exactly as today. It said: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
elif ! printf '%s' "$out" | grep -q 'build-converge'; then
  no "end-3: 'run-loop.sh --list' no longer lists build-converge, so the default strategy is unreachable by name. It said: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"
else
  ok "end-3: an ordinary run-loop.sh invocation still behaves as it does today"
fi

gate_done
