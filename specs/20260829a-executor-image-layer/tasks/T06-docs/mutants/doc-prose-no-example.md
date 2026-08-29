# MUTANT: ac1
# TARGET: docs/executors.md
# WHY: describes the FROM harness-base pattern in prose and in a table, but ships no actual
# WHY: Dockerfile block. Every keyword grep passes. A reader has nothing to copy, which is the
# WHY: one thing a worked example is for — and an untested example is a bug handed to the reader,
# WHY: so "we described it carefully" is exactly the failure mode.

# Bringing your own executor

The harness is built in three layers. The loop never varies. The strategy varies per run.
The binding and its CLI are the extension point — that is the layer you change.

| layer | artifact | varies |
|---|---|---|
| the loop | run-task.sh, run-loop.sh, ralph-*.sh | never |
| the strategy | a .conf declaring STRATEGY_PHASES | per run |
| the binding | exec-<tool>.sh plus its CLI | per image |

To add Claude, start from harness-base, install the CLI you want, drop in an exec-claude.sh
binding and a strategy conf that names it. Nothing in the harness repo has to change.

The harness ships no credentials. Auth belongs to your derived image and to the operator
running it.

Note that exec-container.sh runs the loop on the host and sends each prompt into a fresh
container, whereas in a Kubernetes Job the loop is already inside the pod and uses a direct
binding.

This does not give you a Kubernetes Job body, code egress (nothing here pushes a branch or
opens a pull request), or credential provisioning.
