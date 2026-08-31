# Amendments — ratified changes to the constitution

> Version: 2.0.0 · rides with `constitution.md` as Tier-1 context.
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

## Portability follows the invoker, not the tool

Status: Accepted · 2026-08-29 · Source: `specs/20260829a-executor-image-layer/evidence/2026-08-29-writing-the-first-mutant-corpus.md`

Which machines a tool must run on is decided by **who invokes it**, not by what it
does.

- **A human invokes it while authoring** — a gate, `gate-selftest`, `run-loop.sh`,
  anything you reach for while writing a spec. It must run on macOS **and** Linux.
  Use `bound` (`scripts/bound.sh`), never `timeout`; resolve a path with `pwd -P`
  before computing a prefix from it; assume bash 3.2 and BSD userland.
- **Only the runtime invokes it** — `ralph-build.sh`'s watchdog, anything that runs
  exclusively inside a container the harness declares. It may assume that
  container, and `timeout` there is correct.
- **Neither may require a homelab.** No Beelink, no cluster, no private shim. The
  homelab is where we run this, not what it needs.

The seam is not fussiness about platforms. **A tool that cannot run where it is
authored stops being run, and nothing announces that.**

**Rationale:** every portability failure in this repo has been the same one — GNU
coreutils against BSD userland — and the README already carried rules for it,
written after `loop-metrics.sh` used `stat -f %z` and silently measured the wrong
thing on Linux for every task in every container. Those rules were incomplete in
the direction nobody checked.

`scripts/gate-selftest.sh` bounded each gate with `timeout`. macOS ships neither
`timeout` nor `gtimeout`, so on the machine where gates are authored it exited 127
before running a single one — and reported **every mutant as `WRONG-REASON`**,
the verdict that means *"your mutant missed"* and sends the author to rewrite
checks that were already correct. All eight of that spec's own gates were red for
the same reason.

The cost was not a bad afternoon. The tool shipped 2026-08-28 with a spec, a gate,
and **zero mutants in the repo** — and its own outcome calling for a corpus went
unmet. That reads as neglect and was not: the tool worked in the container where
it was built and failed in the one place authoring happens. A second defect hid
behind the first, invisible until it was fixed, because the tool never got far
enough to compute a path.

Corollary, from the same session: **a check must be affordable by the tooling meant
to keep exercising it.** One assertion was rewritten behaviourally, correctly, and
took 41s per gate run — over `gate-selftest`'s own 30s bound, so every mutant in
that corpus came back `HUNG`. The most rigorous version made the corpus unrunnable,
which here means it quietly stops being run: the same end state as a false green,
reached from the opposite direction.

## The constitution carries harness law only; a consumer brings its own

Status: Accepted · 2026-08-30 · Source: issue #71 / the extraction that copied a consumer's law wholesale

The constitution binds every repo Jig runs against, so it may contain no
consumer-specific law — no deploy stack, no secret tooling, no hostnames, no
one repo's file layout. A consumer carries that as its own overlay: its
`specs/constitution.md` and `specs/amendments.md`, assembled **after** the
generic law (the judge anchors the harness pair first). An absent overlay
declares nothing and the loop proceeds; a missing harness constitution is
fatal.

**Rationale:** at extraction this repo shipped pi-cluster's constitution
unedited, so for four days every judge review anchored GitOps-via-Flux,
1Password paths and homelab hostnames as "non-negotiable architectural DNA"
for a repo that has none of them — and cited an `ARCHITECTURE.md` that does
not exist here. Founding law that describes someone else's house is worse
than none: it teaches the reader to discount the parts that are real. The
split was executed by `specs/20260830c-constitution-split/` and this
amendment ratifies the rewrite, which is why the version above goes MAJOR:
redefining the constitution's scope is exactly the change that "should make
you pause."
