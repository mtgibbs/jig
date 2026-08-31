# Constitution — Jig's founding law

> Tier-1 context: the judge anchors this file and `specs/amendments.md` on every review,
> and any agent working a spec in this repo inherits both. Kept deliberately short so it
> always fits the budget. Deep reference is on demand: `specs/README.md` (the method and
> the index of this repo's specs), `specs/TEMPLATE.md` (the spec skeleton), `docs/`
> (runbooks), `AGENTS.md` (the executor's own lean Tier-1 — same law, sized to a small
> context window).

## The convention (non-negotiable)

- **A repo participates by shipping spec directories** — `spec.md`, `tasks.txt`,
  `verify.sh` — and nothing else. Jig never asks the repo for machinery.
- **The gate decides done, never the model.** `verify.sh` is the only voice that can say
  a task is complete. Editing a gate to make work pass is the one unrecoverable move.
- **PR to publish, always.** Output is reviewed before it lands anywhere live — the
  checkpoint is the point. Optimize for a diff a human can verify against the spec's
  acceptance criteria.
- **Evidence is the record.** Everything a run leaves behind is keyed by spec slug under
  `.evidence/` and committed. `null` and `0` are different values. Every classification
  cites the literal marker it matched; a verdict that cannot cite is `unknown`, never a
  guess.

## Git discipline — one worktree per agent (non-negotiable)

Parallel agents race on a shared checkout. The rule that lets loops fan out safely:

- **Each agent loop runs from its OWN `git worktree` on its own throwaway branch.** The
  loop refuses `main`; don't run one from the primary checkout.
- **Before any commit, verify the branch:** `git branch --show-current`. If it's not the
  branch your task was opened on, STOP and ask. Committing default-branch work onto a
  feature branch is just as wrong as committing straight to `main`.
- **Operator setup, the pattern:**
  ```bash
  git worktree add ../<repo>-<task> -b <agent>/<task>   # isolated dir + branch
  cd ../<repo>-<task>
  scripts/run-loop.sh <strategy> specs/<feature>
  ```
- **PR back deliberately** ("PR to publish" above); teardown when the task lands:
  `git worktree remove --force ../<repo>-<task>`.

## Gates — the three-verdict contract

- Three verdicts: `PASS` · `FAIL` (the artifact exists and is wrong) · `pend` (it does
  not exist yet); `STRICT=1` promotes every pend, and the final task always runs strict.
  Presence-gate on the **artifact**, never on a task number.
- **Gates must prove they can fail** (`specs/amendments.md`): red-before / green-after,
  recorded in the spec's `evidence/`.
- **Name the states a check must tell apart** (`specs/amendments.md`): a check that can
  only ever report the benign verdict is not a check at all.
- Read `specs/TEMPLATE.md` §11 before writing one — the traps in there were each paid
  for.

## Portability (non-negotiable)

- Jig is **authored on macOS and runs in Linux containers**, and which rules bind a file
  follows from **who invokes it** (`specs/amendments.md`, "Portability follows the
  invoker"). Anything a human reaches for while authoring runs on both: bash 3.2 is the
  floor, `bound` never `timeout`, GNU before BSD in any `stat` fallback, `pwd -P` before
  computing a path prefix.
- **Neither authoring nor runtime may require private infrastructure.** A clone, a
  shell, and a model endpoint are the whole dependency list.

## Anti-novelty directives (READ THIS)

This is a **conventional, mature codebase — not a greenfield**. Your job is to fit in,
not to innovate.

- **Reuse the existing pattern. Cite the file you copied from.** If similar machinery
  already exists, mirror it.
- **Do not invent URLs, paths, ports, or API shapes.** If a value isn't given in the
  spec, it's an open question — flag it, don't guess.
- **Beware the *similar-but-different* trap.** When two existing patterns look alike,
  the spec says which to follow and how they differ — honor that over your instinct to
  copy the nearest one.
- **Stay in scope.** Do exactly what the spec's tasks say; don't "helpfully" refactor or
  touch adjacent things.

## Specs & verification (for whoever authors a spec)

- **Worked examples must be tested before handoff.** A literal executor copies your
  example faithfully — bugs and all. An untested example is a bug you've outsourced.
- **Verification is external and mandatory.** Every spec ships a `verify.sh` — the
  acceptance criteria compiled into a deterministic gate. The loop runs it; **the model
  never self-certifies "done".**
- **One task per loop iteration, fresh context.** Decompose; never hand the model the
  whole repo or whole spec at once. Small scope = small context = reliable, fast, cheap.
  The fixture (loop) carries the rigor, not the model.
- **Verify the exact thing a criterion depends on — not a proxy.** An item existing is
  not its field existing; resolve at the right granularity, and don't let tooling
  friction silently downgrade a field-level check to an item-level one. If you can't
  verify it now, it's an open question, not a fact.
- **Research the idiomatic, *tasteful* pattern before specifying** — not just the first
  correct one (`specs/design-principles.md`). Taste needs an eye on the rendered
  artifact; static gates can't see "this looks dumb".

## The consumer overlay — where a repo's own law lives

This file is **harness law only**: it binds every repo Jig runs against, so nothing
consumer-specific belongs here — no deploy stack, no secret tooling, no hostnames, no
one repo's file layout. A consumer repo brings that as its own overlay: its
`specs/constitution.md` and `specs/amendments.md`.

- **Assembly order: generic first, overlay second.** The judge anchors Jig's
  constitution and amendments, then the target repo's own pair — the order is load-
  bearing and gated (`scripts/ralph-judge-codex.sh`). Inside a consumer repo, the
  `Constitution:` line in a spec's header points at that repo's overlay.
- **An absent overlay declares nothing, and the loop proceeds** — the same rule as an
  absent manifest key. A missing *harness* constitution is fatal: a judge with no
  principles to cite must refuse, not report "nothing found".
- When Jig runs its own specs, law and overlay are the same file reached two ways; the
  judge dedupes on identity.

## Amendments

`specs/amendments.md` rides with this file as Tier-1 context and is **append-only**.
The constitution is founding intent — it does not morph. Change arrives as an amendment,
ratified by a human via the PR that adds it; judges cite an amendment by its heading,
same as a constitution principle.
