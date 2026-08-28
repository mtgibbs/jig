# Amendments — ratified changes to the constitution

> Version: 1.3.0 · rides with `constitution.md` as Tier-1 context.
>
> The constitution is founding intent. **It does not morph.** Change arrives here:
> proposed from the memory notes (`memory-amend propose`), ratified by a human via
> the PR that adds it, appended — never edited into the original.
>
> Rules for this file:
> - **Append-only.** A superseded amendment gets `Status: Superseded by <heading>`,
>   never deletion — the history is the point.
> - **Semver on the version line above.** New principle = MINOR. Wording fix = PATCH.
>   Removing or redefining one = MAJOR, and should make you pause.
> - Every amendment names its **Source** note, so the trail back to where it was
>   learned survives.
> - Judges cite an amendment by its heading, same as a constitution principle.

## Gates must prove they can fail

Status: Accepted · 2026-08-10 · Source: pi-cluster/reference_loop_library

A `verify.sh` check must be shown to go RED without the change it verifies —
red-before / green-after — not merely green with it. A check that has never
failed proves presence, not correctness; it cannot catch "built nothing."

**Rationale:** false-green is the strongest failure mode of deterministic
gates (the `no_false_green` risk; the specs/export incident scored an empty
deliverable as passing). Proposed in the notes 2026-07-27 from the Loop
Library review; ratified via memory-amend + this PR.

## Durable facts go to the repo, never only to memory

Status: Accepted · 2026-08-10 · Source: pi-cluster/feedback_docs_over_memory

A non-obvious fact about the cluster or a service — API quirk, breaking
default, hour-long recipe — lands in the repo: a skill's `SKILL.md`, `docs/`,
or `ARCHITECTURE.md`. Agent memory holds the user profile, feedback rules,
ephemeral state, and pointers to docs — never the content itself. When in
doubt, write the doc.

**Rationale:** memory is private to one agent — it survives no rebuild, gets
no PR review, and is invisible to sub-agents and humans reading the repo.
Docs travel with the codebase. This principle already decided all six
amendment declines before it was ratified itself.

## PR to publish, always

Status: Accepted · 2026-08-14 · Source: rethink-memory-and-visualization/feedback-pr-to-publish

Anything that lands somewhere live — a protected branch, a deployed service, a
published page, a wall display — arrives by PR. Generated artifacts included.
Never push around a protected branch; move the commit to a branch, open the PR,
let the gates run, merge. A human or a designed gatekeeper reviews every
publish — the checkpoint is the point.

**Rationale:** the checkpoint is where the machine checks itself. The day this
was ratified, the drift gate blocked an atlas publish because a generated doc
was stale — and printed the exact fix. A direct push would have skipped it.
Branch protection is the decision, not an obstacle.

## Name the states a check must tell apart

Status: Accepted · 2026-08-28 · Source: 20260828i-per-task-gates / the gate-defect run

Every check — a gate assertion, a presence guard, a liveness poll, a monitor —
maps observations onto verdicts. Its characteristic defect is not being *wrong*
but being *blind*: two materially different states produce the same reading, and
the benign one wins silently.

Before writing the check, name the states it must distinguish. Then run it
against one input per state and confirm each produces a different reading. A
check exercised against only one state has not been validated; it has been
demonstrated.

The dangerous direction is always the one that reads as fine — `pend`, `skip`,
`clear`, `PASS` — because nothing announces it. A check that can only ever
report the benign verdict is not a weak check, it is not a check at all.

**Rationale:** six instances in one day, all the same shape, none caught by
reading:

| check | states it conflated | it always said |
|---|---|---|
| `grep -q '501'` guarding a 501 assertion | not built · built wrong | pend |
| `grep 'x y' /proc/*/cmdline` (NUL-separated) | running · stopped | stopped |
| one `fx.out` shared by every fixture | fixture A's output · fixture B's | whichever ran last |
| `case $TRACE in *T01*)` | unbuilt · built and broken | pend |
| fixtures whose gates all exit 0 | gate passed · gate failed | never asked |
| `grep -c` on single-line JSON | 1 occurrence · N occurrences | 1 |

The `/proc` poll is the clearest case: it reported "the loop ended" every time
it ran, including while the loop was mid-attempt. Its first report happened to
be true, which is precisely what made the second one credible — and acting on
it overwrote work that had already passed its gate.

This extends "Gates must prove they can fail" in two directions. It applies to
**every** check, not only to gates: the poll and the monitor above were not
gates and cost the most. And it names what to do when a check *can* fail but
still misleads — enumerate the states, then prove one reading per state.

Corollary for mutation testing: a mutant must be confirmed to exercise the code
path its assertion covers. A mutant that misses reads exactly like an assertion
that cannot detect it, and sends you rewriting a correct check.
