# Spec: the product is named Jig — identity renames, the bones do not

- **Status:** Done v1.0 — name ratified 2026-08-30 (closes #75 OQ1: **Jig**; OQ2: repo slug
  renames to `mtgibbs/jig`; runtime surface deferred, see §12)
- **Owner:** Matt (design by Claude; executed by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, grep
- **MCP:** none
- **Permissions:** write:README.md, write:AGENTS.md, write:docs/**, write:scripts/dispatch/board.html, write:scripts/runboard.py, write:scripts/dispatch/coordinator.py
- **Touches:** `README.md`, `AGENTS.md`, `docs/{coordinator,run-control,loop-container}.md`,
  `scripts/dispatch/board.html`, `scripts/runboard.py`, `scripts/dispatch/coordinator.py`.
  **No change** to any `ralph-*.sh`, any `RALPH_*`/`HARNESS_*` variable, any evidence-schema
  literal, exit code, gate verdict string, or GHCR image name.

---

## 1. Why · [R — Requirements]

"Harness" collides with the industry term for the scaffolding *inside* agent products, which is
precisely the confusion outsiders have ("isn't that just Claude Code?"). The project needs a name
that carries its actual identity: an operational convention where "done" is a deterministic
artifact of the repo, plus an epistemics layer that makes a run's own reports incapable of lying.

**The name is Jig.** A jig is the machine-shop fixture that holds the work and guides the tool so
a literal, unskilled operator produces precise output every time — the repo's own thesis: *"The
fixture (loop) carries the rigor, not the model."* It comes from the machine-shop metaphor family
already running through the repo (stamper, fixture, gates, inspector), not from a new theme.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The README opens with the product name and the one-line definition: *a repo brings a spec and
   a gate; Jig owns everything else.*
2. Every board title (fleet board, run board, coordinator fallback page) carries the name.
3. `AGENTS.md` and the `docs/` guides introduce the project as Jig.
4. Not one schema literal, env var, script name, exit code, gate verdict, or image name changed —
   the name is a coat of paint on stable bones.
5. "Drift" is used for exactly one concept in the docs, defined where first used.

## 3. Entities · [E — Entities] — what renames, and what never does

| layer | examples | this spec |
|---|---|---|
| identity prose | README, AGENTS.md, docs guides | **renames** |
| display titles | `board.html`, `runboard.py`, `coordinator.py` fallback page | **renames** |
| repo metadata | GitHub description, repo slug (`mtgibbs/harness` → `mtgibbs/jig`) | **renames** (outside the tree; GitHub redirects the old slug) |
| runtime surface | `ralph-*.sh`, `RALPH_*` vars, `ralph_*` functions | **frozen** — consumers (pi-cluster ~90 refs, notes-from-hearing ~55) depend on it; own spec later, with shims |
| dispatch layer | `HARNESS_*` vars, `mcp-harness`, `harness-coordinator` image | **frozen** — separate decisions if ever |
| record | `specs/2026*`, `.evidence/`, `docs/runs/`, quoted history | **never** — rewriting a record to satisfy a rename falsifies it |

## 4. Approach · [A — Approach]

Prose-first, deliberately: identity is earned in the artifacts before any breaking rename. Where
the old name appears inside a quotation or a run record it stays byte-for-byte — the extraction
story in the README *quotes* pi-cluster ADR-008 and issue #195, and those said "harness" when
they were written. The README notes the rename once, where the history is told.

**Rejected: renaming the runtime surface in the same cut.** A rename either breaks a path-keyed
guard loudly or disarms it silently (measured twice — see `20260828c-strategy-file-extension`
§6), and this repo's own historical gates grep for `ralph-build.sh` by name. That work needs its
own spec, compat shims, and a consumer migration.

## 5. Scope · [S — Structure: boundary]

### In scope
The files in **Touches**, prose and title strings only.

### Out of scope
`scripts/*.sh` behaviour, `scripts/loops/`, `docker/`, `.github/`, `specs/2026*` (records),
`.evidence/`, `docs/runs/`, `docs/adr/`, `specs/constitution.md` and `specs/README.md` (owned by
#71's constitution split), `scripts/dispatch/README.md` and `scripts/loops/README.md` (component
contracts with their own gates).

## 6. Prior decisions / facts the implementer must know · [S]

- Issue #75 drafted this spec and its acceptance criteria; the user ratified **Jig** and the repo
  slug rename on 2026-08-30.
- GHCR image names are hardcoded in `.github/workflows/build-images.yml` (`loop-executor`,
  `harness-coordinator`) under `ghcr.io/mtgibbs/` — user-scoped, so the repo slug rename does not
  move them.
- Gates from `20260828f/g/h` grep `scripts/dispatch/README.md`, and `20260829a` greps
  `scripts/loops/README.md` — neither touches the root README or board titles.
- The one "drift" use in identity docs is `README.md` ("three specs had to police for drift") —
  the generic code-copy sense. pi-cluster's drift *gate* is that repo's concept and is not used
  here.

## 8. Safeguards · [S — Safeguards]

- The rename shall not alter any evidence-schema literal, env var name, script filename, exit
  code, or gate verdict string. Each maps to an §11 invariance assertion.
- Quoted history keeps its original wording.

## 9. Task breakdown · [O — Operations]

- T1: README — retitle to Jig, open with the one-line definition, sweep identity prose, note the
  rename where the extraction history is told, define "drift" at its first use.
- T2: Board titles — `board.html` `<title>`/`<h1>`, `runboard.py` `<title>`/`<h1>`,
  `coordinator.py` fallback page title.
- T3: `AGENTS.md` and `docs/{coordinator,run-control,loop-container}.md` — introduce the project
  as Jig; runtime names (`ralph-build.sh`, `RALPH_*`) stay, they are still the real names.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- AC1 (Ubiquitous): The README's opening shall state the product name and the one-line definition
  ("a repo brings a spec and a gate; Jig owns everything else").
- AC2 (Ubiquitous): The fleet board, run board, and coordinator fallback titles shall carry "Jig".
- AC3 (Unwanted): If any `ralph-*.sh` script, the `RALPH_EXEC_CMD` binding variable, the
  `harness-coordinator` image name, or the loop-doctor outcome vocabulary is renamed, then the
  gate shall fail.
- AC4 (Ubiquitous): The README's first use of "drift" shall carry its definition on the same line.
- AC5 (Unwanted): If "Harness Fleet" or "Harness Run Board" survives anywhere under `scripts/`,
  then the gate shall fail.
- AC6 (Ubiquitous): `AGENTS.md` shall name the project Jig in its opening brief.

## 11. Verification — `verify.sh`

Compiled from §10; static, offline, three-verdict. The invariance checks (AC3) are presence
greps, so their failure condition is exactly the forbidden rename — they cannot be satisfied by a
broken probe returning nothing. Red-before-green run recorded in
`evidence/2026-08-30-red-before-green.md` per the amendment.

## 12. Open questions

- OQ1 (ratify the name) — **resolved: Jig**, 2026-08-30.
- OQ2 (repo slug) — **resolved: rename to `mtgibbs/jig`**; GitHub redirects, images unaffected (§6).
- OQ3 (runtime surface) — **deferred by decision**: `ralph-*.sh` → `jig-*.sh` and `RALPH_*` →
  `JIG_*` land later behind their own spec with compat shims and a consumer migration; tracked in
  a follow-up issue.
