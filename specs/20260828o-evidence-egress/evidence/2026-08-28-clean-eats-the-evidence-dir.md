# A vanished evidence directory is reported as "the executor did not start"

Observed 2026-08-28 while building this spec's fixtures, before any implementation existed.

## What happens

The loop's between-attempt reset runs `git clean -fd`. If `.evidence/` is untracked and not
ignored, that deletes it. Every write afterwards fails:

    scripts/ralph-log.sh:  .../T1-attempt2.prompt.md: No such file or directory
    scripts/ralph-build.sh: .../T1-attempt2.log: No such file or directory
    ✋ ABORT: the executor did not start (exit 1, 0B of output)
              — the container needs attention, not another retry.

The executor started, ran, and wrote a file. What actually failed was creating the transcript it
would have been measured by, and "0 bytes of transcript" is indistinguishable from "produced no
output" to the check that reads it. The run then aborts with a diagnosis pointing at the
container.

## Why it matters beyond the fixture

The production repo is protected only by its own `.gitignore` carrying `.evidence/runs/`. A
`git clean -fdx`, a fresh clone whose ignore rules have not landed, or any spec whose fixture repo
lacks that entry reproduces it. `hb_write` already hit the same defect from the same cause and was
fixed by recreating the directory rather than skipping the write — the artifact writers have the
same exposure and no such guard.

This is the state-conflation shape again: two very different situations, a broken executor and a
missing output directory, produce one reading, and the reading names the wrong subsystem.

## Status

Not fixed here — this spec is about egress, and widening it to cover writer robustness would make
one task carry two unrelated changes. Filed so it is not rediscovered from scratch. The fixture
works around it with `mkloop_logged`.

---

# Gate validation state at hand-off

T1's gate was validated and the other three were not. Recorded so the next reader knows which
assertions have been observed to work and which have only been written.

| gate | validated | how |
|---|---|---|
| T01 push-artifacts | **yes** | 8/8 against a reference implementation; 4 FAIL / 4 PASS against unbuilt main; mutants killed ac1 and ac5 |
| T02 bound-payload | no | written, never executed |
| T03 push-transcript | no | written, never executed |
| T04 docs | no | written, never executed |

Five defects were found in T01's gate by RUNNING it, none by reading it:

- `gate_tmpdir` sets `T` as a side effect and prints nothing, so `T="$(gate_tmpdir)"` discarded
  the assignment. ac1 then compared two files that did not exist and reported them identical — a
  gate measuring nothing and passing.
- `grep -c` prints `0` **and** exits 1, so `arts() { grep -c … || echo 0; }` returned two lines.
  Every numeric test errored, and a failing `[ ]` sends an if/elif chain to its `else`, which is
  the PASS branch. Two assertions passed against an implementation that did not exist.
- `coord_start` never cleared its port file, so a second call returned the first, already-killed
  server's port. One false FAIL against a correct implementation.
- ac1's control comparison was unstable: two fixture commits land in the same second and git
  breaks the tie arbitrarily, so main failed against main.
- ac4 owned the "token is not in the URL" check, which belongs to ac8. A mutant moving the token
  into a query string therefore tripped three other assertions and never reached the one written
  for it — WRONG-REASON, not a kill.

Two defects were found in `gate-selftest.sh` itself, both now fixed:

- WRONG-REASON reported that a mutant missed but not what it hit instead, which is the only fact
  needed to fix it. It now prints the assertions that actually failed.
- The hermetic workspace deletes `.git` and re-inits, so `origin/main` never exists — and
  comparing behaviour against main is how the portability assertions pin their control. Every
  mutant against such a gate returned WRONG-REASON for an environmental reason. The workspace now
  fetches that one ref across.

The mutants themselves are deliberately NOT committed. A mutant is a complete replacement file,
so for a 500-line script it carries the whole correct implementation minus one defect — checking
them in would hand the executor the answer it is supposed to write. This is a real limit of
mutation testing on large targets and is worth solving properly rather than working around.

Cost note: each run of T01's gate spawns real ralph loops and takes roughly five minutes, so one
mutation pass over four mutants is twenty minutes. That economics, not the method, is why the
remaining gates were left unvalidated.
