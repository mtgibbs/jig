# Jig

**A repo brings a spec and a gate; Jig owns everything else** — the loop, the judge, the retry
contract, the evidence, and the telemetry. A jig is the machine-shop fixture that holds the work
and guides the tool so a literal operator produces precise output every time: *the fixture
carries the rigor, not the model.*

Born as "harness", extracted from `mtgibbs/pi-cluster` on 2026-08-26 under the trigger set by
that repo's `pi-cluster/docs/adr/008-review-hub-framework-seam.md`:

> Extract to its own repo when a **second repo or cluster** wants the harness.

`notes-from-hearing` became that second consumer, followed the convention (pi-cluster #195 —
*"a project brings specs and gates; the harness owns the rest"*), deleted its harness copy, and
consequently could not be dispatched to at all. This repo is the fix. Renamed **Jig** on
2026-08-30 (#75): "harness" has come to mean the scaffolding *inside* an agent product, which
this is not — quotes and run records keep the old name, and so does the runtime surface
(`ralph-*.sh`, `RALPH_*`) until its own migration spec lands.

## The convention

A repo participates by shipping spec directories. Nothing else.

```
<any repo>/
├── specs/<feature>/
│   ├── spec.md          the generative expectation — rebuildable-from, not a changelog
│   ├── tasks.txt        one task per line: "T1: do the thing"
│   └── verify.sh        the eval. Deterministic. The ONLY voice that can say "done"
└── .evidence/           Jig writes here; commit it, it is the record
```

Jig never asks the repo for machinery. If a spec dir has those three files, the loop can
run it.

## Running it

```bash
scripts/run-loop.sh build-converge   specs/<feature>   # build until the gate is green
scripts/run-loop.sh build-then-judge specs/<feature>   # then a cross-family judge pass
scripts/run-loop.sh judge-refine     specs/<feature>   # judge an already-green gate
scripts/run-loop.sh --list
```

Run from a git worktree on a throwaway branch — the loop refuses `main`.

A **strategy** is one `scripts/loops/<name>.conf`: which phases run, plus the bindings they need.
It may only declare `STRATEGY_DESC`/`STRATEGY_PHASES` and export knobs the loop already accepts.
New behaviour belongs in a loop script, behind its own spec and gate.

## Executors are bindings, not forks

`ralph-build.sh` drives whatever `RALPH_EXEC_CMD` points at. A binding takes the prompt as `$1`,
reads `ROOT` from the environment, and writes the transcript to stdout. The loop owns tasks,
gate, retries, evidence and the watchdog.

| binding | executor |
|---|---|
| `scripts/exec-opencode.sh` | `oc run` — the default when `RALPH_EXEC_CMD` is unset |
| `scripts/exec-codex.sh` | `codex exec` |

Adding an executor is a binding plus a `.conf`. It used to be a 204-line copy of the whole loop
that three specs had to police for drift — copies of the same machinery diverging, which is the
only thing "drift" means in these docs (pi-cluster #199).

## Evidence

Everything a run leaves behind is keyed by **spec slug**, so a feature's whole record is one
directory walk:

```
<repo>/.evidence/
  runs/<spec-slug>/<agent>-<pid>/<task>-attempt<n>.{log,diff}   gitignored (bulky)
  status/<spec-slug>/<agent>-<pid>.json                          committed
  judge/<spec>/{ledger.jsonl,report.json}                        committed
  index.md · index.jsonl · metrics.jsonl                         committed, derived
```

Two rules that are easy to break by accident:

- **The slug is a directory level, never part of the leaf.** Readers parse `<agent>-<pid>` out of
  the leaf. Folding the slug in gives a pid of `asset-ladder-37173`, which matches no status file
  — the index still generates, with every run silently unattributed.
- **Sweep at the run level, not the spec level.** A directory's mtime tracks its newest child, so
  reaping at depth 1 takes a feature's entire history the moment it goes quiet.

## Reading the record

```bash
scripts/loop-doctor.sh                 # one line per run, with the fault named
scripts/loop-doctor.sh --json          # machine-readable, per §3.2 schema
scripts/loop-index.py --repo <dir> --spec specs/<feature>
scripts/loop-report.sh                 # one-screen branch summary
```

`loop-doctor` classifies rather than dumps: `dead` · `running` · `done` · `watchdog-kill` ·
`permission-blocked` · `executor-stillborn` · `verify-fail` · `no-op` · `unknown`. Every row
cites the literal marker it matched; anything that cannot cite is `unknown`, never guessed.

## The navigation codesheet

Every headless run prepends a repo map plus the reference sheet the repo's shape calls for —
symbol graph for code, edge index for manifests, both for mixed. Generated **once per loop** so
the bytes are stable across every task and retry and ride the prefix cache.

- Generator: `scripts/gen-codesheet.mjs` (wraps `scripts/token-bench/gen-*.mjs`)
- `RALPH_SHEET=off` disables it for a loop; `OC_SHEET=off` stops `oc` injecting it twice
- `OC_SHEET_GEN` overrides generator resolution
- Measured on 783 trials: **20–56% less context at equal-or-better accuracy**. Evidence:
  `docs/research/codemap-serena-token-efficiency.md` (research imported from pi-cluster, where
  the trials ran).

## This repo is its own first subscriber

`specs/` here holds Jig's own specs and gates, so a change to Jig is gated exactly the way a
consumer's is. That is not decoration. Before extraction the harness was gated **by
accident of address** — it happened to sit next to pi-cluster's `specs/`. `loop-metrics.sh` is
what that was worth: it used `stat -f %z`, which on Linux **succeeds** and prints filesystem
status instead of a size, so it failed on every task in every container and nothing noticed.

Portability rules that follow from that, and are not optional here:

- **bash 3.2** is the floor (macOS ships it): no associative arrays, no `mapfile`, no `${x^^}`.
- **GNU before BSD in any `stat` fallback.** `stat -f X || stat -c Y` is broken on Linux because
  `stat -f` exits 0 there. Prefer `wc -c` for size — POSIX, no branch to get wrong.
- **`bound`, never `timeout`.** `timeout` is GNU coreutils and macOS ships neither it nor
  `gtimeout`. `scripts/bound.sh` prefers the real one where it exists and falls back to perl, and
  it kills the process **group** — killing only the child leaves grandchildren holding the pipe,
  so the caller inherits the hang it was bounding.
- **`pwd -P` before computing a path prefix.** `pwd` is logical and `git rev-parse
  --show-toplevel` is physical, so under a macOS temp dir one says `/var/…` and the other
  `/private/var/…` and a `${path#$root}` strip silently does nothing.
- Jig is **authored on macOS and runs on Linux**. Which rules apply to a given file
  follows from **who invokes it** — see the amendment *"Portability follows the invoker, not the
  tool"*. Anything a human reaches for while authoring runs on both. Anything only the runtime
  invokes may assume its declared container. Neither may require the homelab.

What that split was worth, the second time: `gate-selftest.sh` bounded gates with `timeout`, so
on the authoring machine it exited 127 before running one and reported every mutant as
`WRONG-REASON` — *"your mutant missed."* The tool shipped with a spec, a gate and **zero mutants
in the repo**, which reads as neglect and was not.

## Amendments

`specs/amendments.md` rides with `specs/constitution.md` as Tier-1 context and is append-only.
The one that matters most here:

> **Gates must prove they can fail.** A `verify.sh` check must be shown to go RED without the
> change it verifies — not merely green with it. A check that has never failed proves presence,
> not correctness.
