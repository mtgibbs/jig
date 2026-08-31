# Spec: 20260831q-spec-scaffolder

- **Status:** In progress v1.0
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/new-spec.sh` (new), `.claude/skills/author-spec/SKILL.md` (new), `specs/TEMPLATE.md`
- **Tools:** git, bash
- **MCP:** none

## 1. Why · [R — Requirements]

The per-task gate convention (20260828i, hardened by 20260831p) is enforced only where the
loop can see it — and it was violated twice on 2026-08-31 by hand-laying spec dirs: once as
a monolithic costume over five deliverables, once by starting to hand-write a `tasks.txt`
for THIS spec. The direction (Matt, 2026-08-31): the convention needs tooling that lays out
the shape *for* the author and validates it deterministically, so the fastest path and the
correct path are the same path. Hand-laid shape is where the hacks live.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `scripts/new-spec.sh <spec-slug> <task-slug>...` scaffolds a spec dir in the canonical
   per-task shape — `tasks/T<NN>-<slug>/verify.sh` per task, single-task included, with
   stub gates that are red by construction and a convergence-only spec `verify.sh`.
2. `scripts/new-spec.sh --check <spec-dir>` validates any spec dir's shape and exits
   non-zero on violations, including a single-task spec without `tasks/`.
3. A `.claude/skills/author-spec` skill teaches scaffold-first authoring; `specs/TEMPLATE.md`
   names the scaffolder and no longer offers the single-task exemption.
4. This spec's own dir was produced by the scaffolder (dogfood: id `20260831q` was
   auto-allocated by the tool).

## 3. Entities · [E — Entities]

The spec-dir shape, pinned: `specs/<YYYYMMDD><letter>-<slug>/` containing `spec.md`,
`tasks.txt` (lines `T<n>: <rich description>`, contiguous from `T1`), `verify.sh`
(convergence-only, executable), `evidence/`, and `tasks/T<NN>-<slug>/verify.sh` (two-digit
zero-padded, executable, one per `tasks.txt` line, no orphans). Slugs: `[a-z0-9-]`, no
leading/trailing dash. Ids: eight digits + one lowercase letter, allocated a→z within a date.

## 4. Approach · [A — Approach]

One bash-3.2-safe script with two modes sharing a `check_spec` core, same house style as
`scripts/ralph-build.sh` (the shape rules mirror its `_validate_task_gates` /
`_gate_for`). The skill is instructions-only; enforcement lives in the script and the loop.
Rejected: a separate linter script (two sources of truth for one shape), and loop-level
refusal of bare single-task specs (would break 20260831c/h gate fixtures that pin legacy
behavior — tracked as a follow-up instead).

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/new-spec.sh`, `.claude/skills/author-spec/SKILL.md`, `specs/TEMPLATE.md` (the
gate-layout section), this spec dir.

### Out of scope
`scripts/ralph-build.sh` — no loop behavior changes; the loop's tolerance of legacy
single-task specs stays (20260831c/h pin it). `specs/lib/assert.sh`. Existing spec dirs.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The loop reads gates via `ls -d "$SPEC_DIR"/tasks/T$(printf '%02d' N)-*` — two-digit
  zero-padded dirs are load-bearing (`scripts/ralph-build.sh` `_gate_for`).
- `Tools:`/`MCP:` header preflight: `none` passes; a placeholder like `<comma-separated>`
  can fail `command -v` — the scaffold emits `none` for both.
- The word ban on the legacy staging verb must strip comments first (TEMPLATE Trap A) and
  build its probe string by concatenation, or the checker and gates trip on their own text
  (this bit 20260831j's and p's gates in comments, twice).
- bash 3.2 floor: no arrays, no `declare -A`, `${1+"$@"}` for empty `"$@"` under `set -u`.

## 7. Norms · [N — Norms]

Match the repo's script house style: `set -uo pipefail`, `die()`/`usage()`, `  FAIL  ` /
`  PASS  ` two-space gate output, physical paths via `pwd -P` (the macOS `/var` →
`/private/var` lesson), fixtures in `mktemp -d` cleaned by an EXIT trap.

## 8. Safeguards · [S — Safeguards]

- A refusal must write nothing — no partial spec dirs (T01 ac4 pins it).
- The scaffold's stub gates must FAIL until authored — a stub that passes would let an
  empty spec ride the loop green (T01 ac2 pins it).
- `--check` must stay deterministic and offline — no network, no date dependence in its
  verdicts.

## 9. Task breakdown · [O — Operations]

- **T1 — create mode** (`tasks/T01-scaffold-create`): `scripts/new-spec.sh` argument
  parsing (`--root`, `--id`, positional slugs), slug/id validation, auto id allocation
  a→z within today's date, and the emitted shape: `tasks/T<NN>-<slug>/verify.sh` stubs
  that exit 1 until authored, convergence-only `verify.sh`, `spec.md` skeleton
  (`Tools:/MCP: none`), `evidence/`, `tasks.txt` with contiguous `T<n>:` lines.
- **T2 — check mode** (`tasks/T02-shape-check`): `--check <spec-dir>` validates the full
  shape and exits non-zero on: missing core files, missing `tasks/` (single-task
  included), missing/extra/misnumbered task dirs, non-executable gates, the staging verb
  as code in any gate (comments stripped).
- **T3 — skill + template** (`tasks/T03-authoring-skill`):
  `.claude/skills/author-spec/SKILL.md` (scaffold-first procedure, red-before-green,
  `--check` before PR, no override) and the `specs/TEMPLATE.md` edit (names the
  scaffolder; the single-task exemption sentence replaced by the still-carries rule).

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **T1** — When invoked with N task slugs, the scaffolder shall create the full per-task
  shape with N stub gates (ac1), each red by construction (ac2), for N=1 as well (ac3).
  If given zero task slugs, an existing dir/id, or a malformed slug, then it shall refuse
  and write nothing (ac4). The tool shall allocate ids a→z within a date (ac5). The real
  loop shall accept a scaffolded spec past validation and judge it by its stub gate (ac6).
- **T2** — `--check` shall pass a fresh scaffold and the real 20260831p spec (ac1), and
  fail on: missing `tasks/` for any task count (ac2), missing or orphan task dirs (ac3),
  missing or non-executable gates (ac4), the staging verb as code — while a comment
  mentioning it stays legal (ac5), non-contiguous numbering (ac6), missing `spec.md` or a
  nonexistent dir (ac7).
- **T3** — The skill shall exist with `name: author-spec` and teach the scaffolder,
  red-before-green, the single-task rule, `--check`, and "no override" (ac1–ac2). The
  TEMPLATE shall name the scaffolder, state that a single-task spec still carries
  `tasks/`, and drop the exemption sentence (ac3).

## 11. Verification — the gates

Per-task gates under `tasks/`, run cumulatively 1..N by the loop; the spec-level
`verify.sh` is convergence-only. Red evidence: `evidence/red-before-green.txt`, captured
with the deliverables absent (`scripts/new-spec.sh` moved aside, skill unwritten, TEMPLATE
unedited) — it is also the positive control for T03's absence probe on the exemption
sentence. Green: `evidence/green-after.txt`.

## 12. Open questions

- OQ1 (resolved → follow-up): should the loop itself refuse a bare single-task spec?
  Not here — 20260831c/h gates pin the legacy tolerance; needs its own spec to rework
  them. `--check` already refuses it, and the skill makes the scaffolder the path.

## 14. Tuning log

- **v1.0 (2026-08-31)** — Authored after two hand-layout incidents the same day (the
  20260831p monolithic costume, then a hand-written `tasks.txt` for this very spec —
  caught by Matt: "you already failed the assignment"). Bootstrap order corrected to
  tool-first: the scaffolder was written before its spec dir, then scaffolded its own
  spec (auto-allocating `20260831q`), and the content was authored into that shape.
