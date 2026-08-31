---
name: author-spec
description: Author a new spec in the canonical per-task shape — scaffold with scripts/new-spec.sh first, gates red-first, --check before the PR. Use whenever creating a spec dir under specs/.
---

# Author a spec

Never hand-lay a spec dir. The shape is tooled, and the tool goes first.

## The shape (there is exactly one)

Every spec — **single-task included** — carries:

- `tasks.txt` — one `T<n>: <semantically rich description>` line per task, contiguous from `T1`
- `tasks/T<NN>-<slug>/verify.sh` — one executable gate per task, two-digit zero-padded
- `verify.sh` — convergence-only: runs the task gates, owns no checks of its own
- `spec.md` — filled per `specs/TEMPLATE.md`
- `evidence/` — `red-before-green.txt` and `green-after.txt`

There is no monolithic shape and no single-task exemption. `ralph-build.sh` refuses a
multi-task spec without `tasks/` (exit 3, no override), and `--check` refuses the
single-task variant too. Do not look for a way around this; if the shape seems to fight
the work, the task breakdown is wrong — fix that.

The legacy staging verb (`pend`) is banned as code in every gate: a task gate asserts only
its own task's criteria, and at convergence "not built yet" is a failure by definition.

## The procedure

1. **Scaffold first:** `scripts/new-spec.sh <spec-slug> <task-slug>...` — one task slug
   per work unit. It allocates the id, lays the full shape, and emits stub gates that fail
   until authored (red by construction). Never `mkdir`/`touch` the shape by hand.
2. **Fill `spec.md`** per `specs/TEMPLATE.md` — rewrite each scaffolded `tasks.txt` line
   to be semantically rich (a vague line lets the work drift to the noun).
3. **Author each `tasks/T<NN>-<slug>/verify.sh` red-first.** Replace the stub with the
   task's real acceptance checks and run them before building — capture the failing run as
   `evidence/red-before-green.txt`. If the deliverable already exists (a pin), red is a
   mutant kill or a stash-and-run, never skipped.
4. **Build until green**, then capture `evidence/green-after.txt` from a full clean run of
   the spec-level `verify.sh`.
5. **Validate before the PR:** `scripts/new-spec.sh --check specs/<id>-<slug>` must pass,
   and the repo's regression sweep (the other specs' gates) must stay green.

## Why this exists

Ratified 2026-08-31 after two same-day incidents of hand-laid shape: a five-deliverable
spec dressed as a single task to ride the (now removed) exemption, then a hand-written
`tasks.txt` for the scaffolder's own spec. Hand-laid shape is where the hacks live; the
tool makes the correct path the fastest one. See `specs/20260831q-spec-scaffolder` and
`specs/20260831p-monolithic-refused-outright`.
