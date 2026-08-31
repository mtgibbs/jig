# Spec: stale references, root debris, LICENSE — the neglect-signal sweep

- **Status:** Done v1.0 — executed 2026-08-30 (closes #74; OQ1 resolved *MIT, owner's call*;
  OQ2 resolved *import*)
- **Owner:** Matt (design by Claude from issue #74's comment research; executed by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, grep
- **MCP:** none
- **Permissions:** write:README.md, write:docs/**, write:scripts/** (comments only),
  write:LICENSE, write:CONTRIBUTING.md, write:.evidence/README.md, write:specs/README.md,
  rename:specs/20260830a-product-naming, delete:tasks/
- **Touches:** `README.md`, `docs/adr/001-harness-dispatch.md`, `docs/design/fleet-dispatch.md`,
  `docs/runs/2026-08-27-evidence-replayable-first-run.md`, `docs/research/` (one import),
  three script docstrings, `tasks/` (delete), `LICENSE` (new), `CONTRIBUTING.md` (new),
  `.evidence/README.md` (new), `specs/20260830a-product-naming/` → `20260830d-`,
  `specs/README.md` (index). **No behavior change anywhere.**

---

## 1. Why · [R — Requirements]

Accumulated debt that individually is small and collectively reads as neglect to a stranger —
the exact impression the repo cannot afford while positioning as a product. A README whose own
example is stale ("a strategy is `scripts/loops/<name>.env`" — the loop resolves `.conf`)
teaches the first thing a reader tries to fail.

The issue's own history is the second argument, and it reshaped this spec: v0.1 hand-enumerated
seven dangling references. One resolved itself when an unrelated spec landed, two were retired
by the constitution split (#71/#82), and the gate's first dry run found **three the list never
had**. So the gate is the deliverable; the list is its expected output.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `verify.sh`'s link resolver walks every backticked repo-relative path in `README.md` and
   `docs/**/*.md` and asserts each resolves — from the repo root, `docs/`, or the citing doc's
   own directory — or carries the `pi-cluster/` external-repo marker. Its extraction must match
   ≥ 20 known-good paths, asserted numerically.
2. No doc describes strategy files with a `.env` extension.
3. The dangling references the resolver found are fixed by the smallest honest means each
   (§6 records the judgment per item), and the four script-docstring citations are pinned by
   targeted checks: `.evidence/README.md` created, `scripts/README.md` citation redirected to
   `scripts/exec-opencode.sh`, the two agent-bus citations marked external.
4. `docs/research/codemap-serena-token-efficiency.md` is imported from pi-cluster with a
   provenance note (OQ2: seven files cite it bare, and it backs the README's 20–56% claim).
5. Repo-root `tasks/` debris is gone.
6. `LICENSE` is MIT (OQ1: permissive by owner's choice — easy inside a company, easy for
   whoever wants to mess with it) and `CONTRIBUTING.md` states: PRs only, specs bring gates,
   red-before-green.
7. The `20260830a` slug collision is resolved — `20260830a-product-naming` →
   `20260830d-product-naming` (worker-credentials held first claim via #66) — and prefix
   uniqueness is gated in general so the next collision fails the day it lands.

## 3. Entities · [E — Entities]

Stateless — a docs/metadata sweep plus one gate. The only shape that matters is the resolver's
path token: a backticked string matching an extensioned repo-relative path, minus placeholders
(`[<>*{}$]`), minus the `pi-cluster/` external marker, minus run-artifact names
(`spec.md`/`plan.md`/`tasks.txt`/`review.md` — a loop writes those into a worktree; they are
prose here, not repo paths).

## 4. Approach · [A — Approach]

Gate first, then the sweep, one PR. The gate mirrors `20260830c-constitution-split`'s AC2
(same extraction shape, same positive-control discipline) widened from three Tier-1 docs to
README + all of `docs/`. It ran RED against the pre-sweep tree (12 FAILs, three positive
controls firing — `evidence/`), then the fixes turned it green. Scripts are deliberately NOT
in the resolver's corpus — their comments cite runtime artifacts (`.evidence/runs/`,
`~/.harness/`) a static resolver cannot judge — so the four known script-docstring defects are
pinned individually (AC3). Rejected: a hand-maintained list of dangling refs (stale the moment
another spec lands — measured, twice, in this spec's own §1).

## 5. Scope · [S — Structure: boundary]

### In scope
The enumerated items only: citation fixes in README/docs, three script comment lines, the
research-doc import, `.evidence/README.md`, `tasks/` deletion, LICENSE, CONTRIBUTING.md, the
`20260830d` rename plus index update.

### Out of scope
Any behavior change (no script logic, no gate semantics of other specs); the agent-bus
scripts' homelab coupling (they cite pi-cluster honestly now; whether they belong here at all
is a separate spec); evidence transcripts under `specs/*/evidence/` (records — never rewritten,
and deliberately outside the resolver's corpus).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The `pi-cluster/` prefix as external-repo marker is `20260830c`'s convention (its AC2 greps
  it out); this spec reuses it, never invents a second syntax. **None of these citations are
  new dependencies** — the repo was extracted from pi-cluster on 2026-08-26 and every marked
  path already pointed there implicitly; the marker makes it explicit and machine-checkable.
- Smallest-honest-fix judgments, per dangling ref found:
  - `README.md` `docs/adr/008-…` (extraction provenance), ADR-001's five pi-cluster infra
    paths, both agent-bus docstrings → **external marker** (content lives there, is about there)
  - `README.md` `scripts/exec-qwen.sh` → **rewrite** to `scripts/exec-opencode.sh` (the actual
    default binding, `ralph-build.sh:53`)
  - ADR-001's bare `fleet-dispatch.md` ×2 → **rewrite** to the real path `docs/design/…`
  - run-doc's `evidence/2026-08-26-…` → **rewrite** to the full spec-dir path
  - `.evidence/README.md` (cited by `loop-index.py` for the ~/.harness timer story) →
    **create** — load-bearing for a stranger reading the joiner
  - codemap research doc → **import** (OQ2): backs the README's quantitative claim
- `20260828c-strategy-file-extension` renamed strategies `.env` → `.conf`; the two README
  mentions and `fleet-dispatch.md:185` predate it.
- Rename direction: worker-credentials merged first (#66), product-naming second (#80) — first
  claim keeps the slug. Blast radius verified before the move: the live references were
  `specs/README.md` and the dir's own verify.sh header; commit messages keep the old slug as
  history and evidence transcripts are records, both untouched.

## 7. Norms · [N — Norms]

Match each file's existing comment voice; a citation fix changes the path and nothing else.
CONTRIBUTING.md stays short — three rules and a pointer at the constitution, not a policy
document. The imported research doc is verbatim except the provenance block and qualified
cross-repo citations, and says so in that block.

## 8. Safeguards · [S — Safeguards]

- **No behavior change**: only comments, docs, and file placement move (maps to: no script
  diff outside comment lines — reviewed on the PR diff).
- **Records are never rewritten**: `specs/*/evidence/` and commit history keep the old slug
  and old paths (maps to: resolver corpus excludes `specs/`).
- **The rename must not silently disarm a guard**: `specs/20260830d-product-naming/verify.sh`
  re-run green after the move; `20260830c`'s index gate re-run green (maps to: evidence).

## 9. Task breakdown · [O — Operations]

- T1: the gate — `verify.sh` with the resolver (corpus README + docs, three resolution roots,
  external marker, ≥ 20 extraction floor), `.env` probe, four pinned script citations, debris/
  LICENSE/CONTRIBUTING presence, slug-prefix uniqueness; every absence assertion behind a
  positive control. Run RED on the pre-sweep tree; record.
- T2: the README + docs citation sweep (§6's judgments), the two `.env` → `.conf` lines, the
  research-doc import with provenance.
- T3: `.evidence/README.md`; the three script-docstring fixes.
- T4: delete `tasks/`; add LICENSE (MIT, Matt Gibbs 2026) and CONTRIBUTING.md.
- T5: `git mv` to `20260830d-product-naming` + its verify.sh header; `specs/README.md` index
  (entry moved, this spec added). Re-run the moved gate and `20260830c`'s gate.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- Every backticked repo-relative path cited in `README.md` and `docs/**/*.md` shall resolve or
  carry the `pi-cluster/` external marker. (AC1)
- The gate's path extractor shall match at least 20 known-good paths, asserted numerically; if
  it collects fewer, the gate shall FAIL naming the count. (AC1)
- No file under `README.md` or `docs/` shall describe strategy files with a `.env` extension.
  (AC2)
- The four script-docstring citations shall each resolve in-repo or carry the external marker;
  if `.evidence/README.md` omits the facts `loop-index.py` cites it for, the gate shall FAIL.
  (AC3)
- `docs/research/codemap-serena-token-efficiency.md` shall exist, carry the 783-trial evidence
  and its pi-cluster provenance. (AC4)
- The repo shall contain no root `tasks/` directory. (AC5)
- The repo shall contain `LICENSE` (MIT text) and a `CONTRIBUTING.md` stating PRs-only,
  verify.sh gates, and red-before-green. (AC6)
- No two `specs/2026*` directories shall share a date+letter prefix, and
  `specs/20260830d-product-naming` shall exist. (AC7)
- Where an absence is asserted (AC1, AC2, AC7), the gate shall first prove the probe fires on
  a planted fixture, else FAIL the control.

## 11. Verification — `verify.sh`

Shipped in this directory; red-before-green record in `evidence/`. Whole-spec gate, inline
three-verdict vocabulary (per `20260830c`; `specs/lib/assert.sh` is for per-task gates).
`pend` maps to artifacts that do not exist yet (LICENSE, CONTRIBUTING.md, the import,
`.evidence/README.md`, the renamed dir); `no` to artifacts that exist and are wrong (dangling
citations, `.env` lines, root debris, the collision). Mutant accounting for the run — which
positive controls fired, and that this spec ships no persistent per-task corpus — is in
`evidence/` (see `20260828k-gate-selftest` for the corpus convention this gate's inline
fixtures are the ephemeral cousin of).

## 12. Open questions

None. OQ1 resolved MIT (owner, 2026-08-30: "permissive… for whomever wants to mess with it,
that license will be how I choose to represent this"). OQ2 resolved import (§6).
