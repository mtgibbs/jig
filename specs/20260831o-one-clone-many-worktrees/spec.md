# Spec: one clone, many worktrees — the entry point's shape is pinned

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red = mutant kill in
  `evidence/`); closes issue #63
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** none (pin-only: no production file changes expected)

---

## 1. Why · [R — Requirements]

Issue #63: the Beelink coding container accumulated **11 separate full clones** of
this repo, one per loop run. Disk was the least of it — three of the eleven held
commits that existed nowhere else, the same stashes were duplicated across all
eleven, and no single `git worktree list` could answer "what is this container
working on". The issue's proposal — worktrees off one canonical checkout — landed
39 minutes after it was filed, as `run-task.sh` T4 (20260829a): clone once at
`$WORKSPACE/$REPO_NAME`, `git worktree add` per run, remove+prune before re-add.

But nothing PINS that shape. The 20260829a gate checks the entry point exists and
is unique; no gate fails if someone regresses `worktree add` back to `git clone`
per run — and the failure mode is silent for months, then costs unpushed commits.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. A gate drives the REAL `run-task.sh` through two specs and a re-run against a
   local fixture remote and pins: exactly one full clone, every run dir a
   worktree, `git worktree list` as the inventory, and re-runs that work.
2. Red is a mutant kill: with `worktree add` swapped for `git clone`, the gate
   fails (recorded in `evidence/red-before-green.txt`).

## 5. Scope · [S — Structure: boundary]

### In scope
The gate; this spec.

### Out of scope (the ops residue, named so it is not lost)
Pointing the coding container's interactive sessions at the canonical checkout
(`HARNESS_WORKSPACE`) and the `~/tmp` reaper — both live in beelink-ansible /
pi-cluster, not this repo. The 11-clone pile was hand-made by sessions predating
run-task.sh; the convention for humans-and-Claudes is the constitution's existing
worktree rule.

## 6. Facts the implementer must know · [S — Structure]

- `HARNESS_DIR` without a `.git` is the "baked" path: no fetch, used as-is — the
  gate copies `scripts/` there so the fixture never touches this checkout or the
  network.
- A consumer strategy (`.harness/loops/fx.conf`, no `STRATEGY_TOOLS`) keeps the
  fixture free of the opencode preflight; `RALPH_EXEC_CMD` flows through
  run-task → run-loop → ralph-build from the environment.
- A worktree's `.git` is a FILE; a clone's is a DIRECTORY. That distinction is the
  whole assertion.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When run-task.sh runs spec A against a fresh workspace, the workspace shall hold
  exactly one full clone, and the task dir shall be a worktree of it. (ac1)
- When it then runs spec B, the clone count shall still be one. (ac2)
- `git worktree list` in the clone shall name both task dirs — the inventory the
  issue asked for. (ac3)
- Re-running spec A shall succeed (remove --force + prune + -B; "runnable exactly
  once per container" stays fixed). (ac4)
- Each run's loop shall actually commit its task in its worktree (the runs are
  real, not vacuous). (ac5)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. Local bare repo as the remote;
baked harness dir; stub executor. Red-before-green is a MUTANT run (worktree add →
clone), because the production behavior already exists — the evidence proves the
gate can fail, which is the amendment's actual demand.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
