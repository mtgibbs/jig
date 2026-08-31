# Spec: mutant observability — the kill/survivor record, and the diff that shows what got through

- **Status:** Done v1.0 — executed 2026-08-30 (closes #84; shipped as `20260830f-` — the issue
  proposed `20260831a-` guessing the date, and it is still the 30th)
- **Owner:** Matt (design by Claude from issue #84; executed by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, jq, python3, diff
- **MCP:** none
- **Permissions:** write:scripts/gate-selftest.sh, write:scripts/mutant-ledger.py,
  write:.evidence/**
- **Touches:** `scripts/gate-selftest.sh` (emission seam; verdict semantics and stdout contract
  unchanged), `scripts/mutant-ledger.py` (new), `.evidence/selftest-*.jsonl` (new store),
  `.evidence/mutant-ledger.{md,html}` (generated), `.evidence/README.md` (one section)

---

## 1. Why · [R — Requirements]

A mutant's verdict is the strongest signal of gate health the repo has — a **SURVIVOR is
precisely "how it got through"**, and a kill's diff shows exactly what defect an assertion
proves it can catch. Until now that signal was write-only prose: tool stdout that scrolls away
and `evidence/*.md` narratives. The owner's framing (2026-08-30): *the value is quickly seeing
what it mutated* — the mutant-vs-target diff — to understand how a survivor got through or what
a kill proves. The diff is the payload; the verdict is its label.

The 2026-08-30 baseline (issue #84 comment) also measured **corpus drift** — mutants written
against targets that have since moved show 100+ ±lines and trend toward WRONG-REASON — which is
invisible without a per-run diff capture.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `gate-selftest.sh` under `SELFTEST_EVID=<dir>` appends one JSONL row per mutant (ts, run_id,
   spec, task, mutant, assertion, target, why, verdict, gate_rc, diff, diff_lines, instead) plus
   a `run_complete` marker carrying the counts. **Unset means not one byte is written** —
   `20260828k` end-1 holds a bare run to a byte-identical tree, and an unconfigured channel is
   not a degraded mode (the `HARNESS_REPORT_URL` rule).
2. The diff is captured **at install time**, metadata stripped, against the target as it is in
   the tree that run measured — the target keeps moving, so the diff is recorded when it is true.
3. `scripts/mutant-ledger.py` renders the store (latest complete run per corpus) into
   `.evidence/mutant-ledger.md` (GitHub-renderable, relative links) and `mutant-ledger.html`
   (the visual board), **survivors first**, deterministically — identical store, identical bytes.
4. The real sweep is recorded and committed: 6 corpora, 31 mutants, with the generated ledger.

## 3. Entities · [E — Entities]

`selftest-<specslug>.jsonl`, one JSON object per line, two shapes:

- mutant row: `ts` ISO-8601Z · `run_id` `<UTCstamp>.<pid>` · `spec` · `task` · `mutant` (file
  name) · `assertion` (declared `MUTANT:` id) · `target` (repo-relative) · `why` (all WHY lines
  joined) · `verdict` `KILLED|SURVIVOR|WRONG-REASON|HUNG` · `gate_rc` int · `diff` (unified,
  labels `target/<path>` / `mutant/<name>`) · `diff_lines` int (± lines) · `instead` (array of
  ac-ids that fired, WRONG-REASON only)
- marker row: `run_complete: true` · `run_id` · `spec` · `task` · `killed` · `survivor` ·
  `wrong_reason` · `hung`

A run with rows and no marker is a partial record; the generator never prefers it.

## 4. Approach · [A — Approach]

Smallest seam: the tool computes every field at the moment it prints prose, so emission is one
function called where each verdict is decided, and the flag mirrors the coordinator's
`HARNESS_REPORT_URL` contract (set = report, unset = line-for-line today's run). The generator
mirrors `loop-index.py`: re-runnable, derives everything from stores, holds no state. Rejected:
emitting by default (breaks `20260828k` end-1); recomputing diffs at render time (lies once the
target moves).

## 5. Scope · [S — Structure: boundary]

**In:** the emission seam, the store, the generator, the recorded baseline sweep.
**Out:** mutant/verdict semantics; new mutant corpora; wiring the fleet board or loop phases to
run the selftest automatically (a later spec — this one makes the record exist and the render
cheap); rewriting existing evidence prose.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `20260828k`'s end-1 gate runs the tool bare and requires a **byte-identical tree** — the
  reason emission is opt-in, verified behaviorally by this spec's ac4.
- The tool's survivor path `exit 1`s **before** the T5 static checks, so emission (rows and
  marker) must complete before the summary block.
- macOS logical-vs-physical paths (`/var` vs `/private/var`): the tool's `pwd -P` fix covers a
  git-rooted CWD; a non-git fixture CWD still resolves logically — this spec's gate builds its
  fixture on a physical path (comment in `verify.sh`).
- WHY parsing: the tool's shell parse keeps only the last `WHY:` line; the emitter re-reads the
  mutant file and joins all WHY lines — richer record, no tool-contract change.
- Verdict vocabulary and the mutant file contract (`MUTANT:`/`TARGET:`/`WHY:`) are
  `20260828k`'s; this spec adds observation, never meaning.

## 7. Norms · [N — Norms]

Emission comments carry the *why* (which gates hold which invariant), matching the tool's
existing voice. The generator's two renders present the same data — no render-only facts. The
ledger's design system: IBM Plex, verdict colors as status (never accent), survivors open by
default, drift badged over 100 ±lines.

## 8. Safeguards · [S — Safeguards]

- **The bare tool stays byte-identical** (maps to ac4, and `20260828k`'s gate re-run green).
- **Stdout contract unchanged** — prose verdicts, summary line, exit codes (maps to ac2's
  prose/row agreement; `20260828k` end-2 re-run green).
- **A partial run never passes for a finished one** (maps to ac2's marker check; the generator
  ignores marker-less runs).
- **The ledger cannot silently go stale or dangle**: ac7 regenerates byte-for-byte from the
  committed store and link-checks every repo path with a planted-bogus positive control.

## 9. Task breakdown · [O — Operations]

- T1: the gate — fixture corpus with one killed, one survivor, one wrong-aimed mutant; schema,
  marker/prose agreement, diff capture, hermetic default, generator behavior, link-check
  controls. RED on the pre-work tree.
- T2: `gate-selftest.sh` — `SELFTEST_EVID` seam: slug/run-id derivation, install-time diff
  capture, per-verdict `emit_row`, `run_complete` marker before the summary exit.
- T3: `scripts/mutant-ledger.py` — store loader (latest complete run per corpus), md + html
  renders, survivor-first, deterministic.
- T4: run the recorded sweep over all 6 corpora; generate and commit the ledger; re-run
  `20260828k`'s spec gate; document the store in `.evidence/README.md`.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When the tool completes a corpus with `SELFTEST_EVID` set, it shall append one row per mutant
  and one marker, and the marker's counts shall equal the prose summary's. (ac1, ac2)
- The emission shall tell all four states apart, proven against a fixture carrying at least a
  KILLED, a SURVIVOR, and a WRONG-REASON (whose row shall name the assertions that fired
  instead). (ac1)
- Every mutant row shall carry a non-empty install-time diff that contains the mutation. (ac3)
- If `SELFTEST_EVID` is unset, the tool shall write nothing — proven behaviorally, with the
  flagged run as the probe's positive control. (ac4)
- When the generator runs, it shall render every row of the latest complete run per corpus,
  survivors before kills, in both md and html. (ac5)
- The committed store shall carry complete runs for ≥ 6 corpora and ≥ 31 distinct mutants; the
  committed ledger shall regenerate byte-for-byte from it; every repo link in it shall resolve,
  with a ≥ 30-link extraction floor and a planted-bogus-link control. (ac6, ac7)

## 11. Verification — `verify.sh`

Shipped in this directory; red-before-green in `evidence/`. Whole-spec gate, inline
three-verdict vocabulary. `pend` maps to the unbuilt (emission, generator, store, committed
ledger); `no` to the built-and-wrong (mis-verdicted fixture rows, marker/prose disagreement,
stale or dangling ledger, an unflagged run that writes).

## 12. Open questions

None blocking. OQ2 from #84 (should loop phases run the selftest automatically, and at what
cost) is deliberately **out of scope** — deferred with the measured baseline (~7s/mutant on
this machine) to the spec that wires fleet phases. OQ3 (capture the transcript for HUNG rows)
deferred until a HUNG verdict actually occurs; the gate output file is already in hand at
emission time, so the seam is ready.
