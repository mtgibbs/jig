# Spec: the constitution carries harness law only — consumers bring their own

- **Status:** Done v1.0 — executed 2026-08-30 (closes #71; OQ1 resolved *yes, by amendment*;
  OQ2 resolved *no new file — the overlay is the consumer repo's own `specs/constitution.md`*)
- **Owner:** Matt (design by Claude; executed by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md` (the artifact under change —
  the split itself is ratified by the amendment this PR appends, per the file's own procedure)
- **Tools:** git, grep
- **MCP:** none
- **Permissions:** write:specs/constitution.md, write:specs/README.md, write:specs/TEMPLATE.md, write:specs/amendments.md
- **Touches:** `specs/constitution.md` (rewrite), `specs/README.md` (rewrite), `specs/TEMPLATE.md`
  (two dangling citations qualified), `specs/amendments.md` (append one amendment, bump version).
  **No change** to any script — the overlay seam already exists in `scripts/ralph-judge-codex.sh`
  and this spec documents and gates it rather than building it.

---

## 1. Why · [R — Requirements]

`specs/constitution.md` is pi-cluster's constitution, unedited since extraction. It is Tier-1
context — the judge anchors it on every review and every spec's header cites it — and it opens
with GitOps-via-Flux, 1Password/ExternalSecrets, `clusters/pi-k3s/...` paths and homelab
hostnames, then cites an `ARCHITECTURE.md` that does not exist in this repo. A stranger's
executor is handed someone else's homelab law as non-negotiables, and it pollutes every piece of
work here. Separately, `specs/README.md` indexes another repo's specs (`homepage-refresh/`,
`decommission-carl-pi-ollama/` — neither exists here) while this repo's own 34 specs have no
index at all.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `specs/constitution.md` contains only harness-generic law: the convention, the gate contract,
   evidence rules, git discipline, portability, anti-novelty, spec authoring, the amendment
   procedure.
2. The consumer-overlay seam is documented where the law lives, with the assembly order stated:
   generic first, overlay second; absent overlay = declares nothing; missing harness
   constitution = fatal.
3. `specs/README.md` indexes this repo's actual specs, every one of them, and no absent one.
4. No Tier-1 document (`constitution.md`, `specs/README.md`, `specs/TEMPLATE.md`) references a
   file absent from this repo.
5. The split is ratified by an appended amendment; `amendments.md`'s version goes MAJOR (2.0.0).

## 3. Entities · [E — Entities]

### 3.1 The seam that already exists

`scripts/ralph-judge-codex.sh:60-63` anchors, in order: harness constitution, harness
amendments, project constitution (`$ROOT/specs/constitution.md`), project amendments. The
`anchor()` function tolerates an absent file (accumulates `ABSENT`, returns); a missing
**harness** constitution is fatal (`exit 2`) before any anchor call. Identical files reached two
ways are deduped on identity — the self-subscriber case. **This spec adds no code**; the gate
pins this shape so it cannot silently regress.

### 3.2 Who consumes which Tier-1

| reader | Tier-1 |
|---|---|
| the judge | `constitution.md` + `amendments.md` (harness pair, then project pair) |
| the executor | `AGENTS.md` — its own lean projection; it never loads the constitution |
| a spec author | the spec header's `Constitution:` line |

`ralph-build.sh` never prepends the constitution — this was verified, not assumed. So "assembly
order" lives in exactly one script, and the gate checks exactly that script.

## 4. Approach · [A — Approach]

Same shape as the executor-binding refactor (`specs/20260825c-executor-binding`): the generic
engine stays here; the consumer brings a small local file. The harness-generic principles are
kept verbatim where possible — it is ratified law, rewrite minimally — and everything
pi-cluster-specific leaves (it returns to pi-cluster as that repo's overlay, in that repo's PR,
not this one). The one lesson embedded in consumer vocabulary (the prowlarr field-vs-item
granularity lesson) keeps its principle and loses its stack-specific citation.

**Rejected: a new `specs/constitution.local.md` file.** The judge already reads the consumer's
own `specs/constitution.md` as the overlay — inventing a second seam beside a working one would
leave two places for consumer law and a resolution question nobody needs. Absent-overlay
semantics follow the manifest precedent (`TEMPLATE.md` §3.2): absent means "declares nothing",
and the loop proceeds.

## 5. Scope · [S — Structure: boundary]

### In scope
The four files in **Touches**.

### Out of scope
Existing `specs/amendments.md` content (append-only — nothing above the new amendment changes
except the version line); any script; gate semantics; `AGENTS.md`; writing pi-cluster's overlay
(that lands in pi-cluster); the stale `judge-loop/spec.md` anchor path in
`ralph-judge-codex.sh:65` (a script ref, not a Tier-1 doc ref — #74's neglect-signal sweep owns
stale script references).

## 6. Prior decisions / facts the implementer must know · [S]

- Dangling Tier-1 refs measured 2026-08-30: `ARCHITECTURE.md` (constitution + README),
  `/CLAUDE.md` (README + TEMPLATE header), `docs/research/local-coding-agent-sdd.md` (README +
  TEMPLATE) — all pi-cluster files. Historical narrative refs without extensions
  (`specs/model-watch`, dirs) don't resolve as file paths and stay as prose citations.
- The two gates that mention the constitution (`20260802a-judge-loop/verify.sh`,
  `20260829c-hermetic-gate` T02 mutant) test behavior — preflight on a dirty worktree,
  fail-closed on a deleted constitution file — never its text. The rewrite cannot break them.
- Old evidence cites "constitution: clean isolated worktree"; the worktree rule keeps its
  heading recognizable so old citations stay resolvable.
- Tier-1 is sized to the budget — the split must not bloat it. The old constitution was 101
  lines; the new one stays in that ballpark.

## 8. Safeguards · [S — Safeguards]

- Amendments are append-only: everything above the new amendment stays byte-identical except
  the version line.
- The judge's anchor order and fail-open/fail-closed split must not change (no script edits at
  all).
- Ratified law rewrites minimally; principles survive even where their citations were
  consumer-specific.

## 9. Task breakdown · [O — Operations]

- T1: Rewrite `specs/constitution.md` as harness law: the convention, worktree discipline, the
  three-verdict gate contract, portability, anti-novelty, spec authoring, the consumer-overlay
  section (assembly order, absent semantics), the amendment procedure.
- T2: Rewrite `specs/README.md`: the method (layers, tiers, EARS, lifecycle) freed of the other
  repo, plus a complete index of every `specs/2026*` directory with a one-line description.
- T3: Qualify `specs/TEMPLATE.md`'s two pi-cluster citations; append the ratifying amendment to
  `specs/amendments.md` and bump its version line to 2.0.0.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- AC1 (Ubiquitous): The constitution shall contain no consumer-specific token — `Flux`,
  `1Password`, `ExternalSecret`, `op://`, `clusters/pi-k3s`, `lab.mtgibbs.dev`, `Beelink`,
  `K3s`, `kubectl`, `Pi-hole`, `Grafana`, `Jellyfin`, `Immich`, `Ollama`, `pi-cluster`,
  `homelab`, `ARCHITECTURE.md`.
- AC2 (Ubiquitous): Every backticked file path in `constitution.md`, `specs/README.md`, and
  `specs/TEMPLATE.md` shall resolve to a file in this repo.
- AC3 (Ubiquitous): `specs/README.md` shall list every `specs/2026*` directory present and no
  directory that is absent.
- AC4 (Unwanted): If `anchor()` in `ralph-judge-codex.sh` stops tolerating an absent file, or
  the missing-harness-constitution path stops being fatal, then the gate shall fail.
- AC5 (Ubiquitous): The judge shall anchor the harness constitution before the project
  constitution, and the constitution's overlay section shall state that order.
- AC6 (Ubiquitous): `amendments.md` shall carry the ratifying amendment (Status: Accepted) and a
  2.x version line, with all prior content byte-identical.

## 11. Verification — `verify.sh`

Compiled from §10; static, offline, three-verdict. The AC1 denylist probe carries a **positive
control**: it is first run against a planted fixture containing `Flux` and must fire, otherwise
the gate fails itself (TEMPLATE §11 Trap B — an absence assertion satisfied by a broken probe).
The AC4/AC5 script checks are region-scoped to the `anchor()` function and the anchor-call
block, not whole-file greps (Trap A). Red-before-green recorded in
`evidence/2026-08-30-red-before-green.md`.

## 12. Open questions

- OQ1 (does changing the constitution require an amendment?) — **resolved: yes.** The file's own
  law says it does not morph; the split arrives as an appended amendment ratified by the human
  merging this PR. MAJOR bump per the semver rule: 1.4.0 → 2.0.0.
- OQ2 (overlay filename; gitignored or absent?) — **resolved: no new file.** The overlay is the
  consumer repo's own `specs/constitution.md` + `specs/amendments.md`, which the judge already
  anchors after the harness pair. Absent = declares nothing, per the manifest precedent.
