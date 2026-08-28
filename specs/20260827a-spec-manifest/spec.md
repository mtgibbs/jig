# Spec: a spec declares what it needs, and the loop refuses to start without it

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor TBD)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md` (+ `/CLAUDE.md` Core Mandates)
- **Touches:** new `scripts/spec-field.sh`; a preflight block in `scripts/run-loop.sh`;
  `specs/TEMPLATE.md` and `specs/README.md` (the grammar). **No change** to `ralph-build.sh`,
  `ralph-judge.sh`, `ralph-log.sh`, `loop-doctor.sh`, or any existing spec.
- **Tools:** git, sed
- **MCP:** none
- **Permissions:** write:scripts/spec-field.sh, write:scripts/run-loop.sh, write:specs/TEMPLATE.md, write:specs/README.md, write:specs/20260827a-spec-manifest/**

---

## 1. Why · [R — Requirements]

A spec says what to build and how it will be judged. It says nothing about **what has to be
present for the work to be possible at all** — which binaries, which executor configuration,
which permissions the tasks will ask for. The loop therefore discovers a missing precondition
the only way it can: by failing a task, burning its retry budget, and stopping for a human with
a symptom rather than a cause.

`loop-doctor` already names one of these faults precisely — `PERM_MARKER='permission requested:'`
at `loop-doctor.sh:27`, matched at `:184`. It is the gitignored `opencode.json` being absent from
the worktree. `scripts/README.md` records that this *"burned six sessions"*, and it **recurred
anyway**, because the knowledge lived in prose nobody greps mid-run.

**loop-doctor names the fault after the run burned. This spec refuses to start.** A precondition
that is checkable in one second before task 1 should never be discovered on attempt 3 of task 4.

The second reason is the direction of travel. Loop containers get exactly the tools they are
given, and a container's tool set has to come from somewhere declarative. The spec directory is
already the only thing a consumer repo contributes — so it is where the declaration belongs.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A spec may declare `Tools:`, `MCP:` and `Permissions:` in the header block it already has.
2. `scripts/spec-field.sh` reads one declared field from a `spec.md`, and is the only thing that
   knows the grammar.
3. `run-loop.sh` preflights the declaration and **aborts before task 1** with a named cause when
   a requirement is absent.
4. A spec with **no** declaration runs exactly as it does today. Every existing spec in this
   repo and every consumer repo is unaffected.
5. **What is enforced and what is merely recorded are labelled as such** — in the template, in
   the preflight output, and in this spec. A field that looks checked and is not is worse than
   no field.

## 3. Entities · [E — Entities]

### 3.1 The grammar — already in use, now contracted

The header block of every `spec.md` is already a key-value list. This spec makes it readable
rather than replacing it:

```markdown
- **Tools:** git, jq, swift
- **MCP:** homelab, memory
- **Permissions:** write:scripts/**, exec:git, net:api.github.com
```

| rule | value |
|---|---|
| shape | `- **<Key>:** <value>` at the start of a line |
| region | above the first `---` horizontal rule, and **only** there |
| list values | comma-separated; surrounding whitespace stripped; empty entries dropped |
| absent key | not an error — it means "declares nothing", never "declares none" |
| `none` | the explicit empty declaration, and it is **not** the same as absent (see §7) |

> **Why not YAML frontmatter.** bash 3.2 is the floor and there is no `yq`; the gate has to read
> this too. `- **Key:** value` parses in one `sed` and already renders in every markdown viewer.
>
> **Why not a fourth file in the spec dir.** The convention's whole claim is that a repo brings
> three files. A fourth is a fourth thing to forget, and one that can drift from the spec it sits
> beside.

### 3.2 The three fields, and their very different weights

| field | meaning | preflight | enforced? |
|---|---|---|---|
| `Tools:` | executables the tasks need on `PATH` | `command -v` each | **yes — fatal** |
| `MCP:` | MCP servers the executor may use | a non-`none` value requires the executor's config file to be present in the worktree | **yes — fatal** |
| `Permissions:` | what the work will ask to do | echoed in the run banner; **nothing verifies it** | **no — recorded only** |

`Permissions:` is deliberately shipped unenforced, and deliberately labelled that way. Enforcing
it needs the container and egress work that does not exist yet. **A permission list nobody checks
is exactly the shape of a gate that cannot fail** (`specs/amendments.md`, "Gates must prove they
can fail"), so the honest move is to record it, say plainly that it is a record, and let the
enforcement land with the mechanism. It is the seam, not the lock.

### 3.3 `scripts/spec-field.sh`

```
scripts/spec-field.sh <spec.md> <Key>     # one value per line, exit 0
scripts/spec-field.sh <spec.md> --list    # every declared key, one per line
```

Exit **0** when the key is declared (including `none`), **1** when it is absent, **2** on a usage
error or an unreadable file. It is the single place the grammar lives; nothing else may parse a
spec header.

## 4. Approach · [A — Approach]

One reader, one preflight block, no new file in the spec directory.

`run-loop.sh` already has the right place: the *"Preflight, all fatal"* block at `:32–38`, which
today checks the strategy name, the spec's files, and the branch. The declaration check joins it,
in the same shape and with the same fatality.

Exit **3** for a missing requirement, not 1 — matching `ralph-build.sh`'s stillborn-executor exit,
which already means *"the container needs attention, not another retry."* That is exactly what a
missing binary is, and a shared code lets a supervisor tell "environment is wrong" from "the work
is wrong" without parsing text.

**Rejected: backfilling the declaration into all twelve existing specs.** It is mechanical, it is
twelve files a model would edit in one task, and none of it is needed for the feature to work —
absence is already the correct default. The template teaches the next spec; the twelve are a
separate, boring change with no design content.

**Rejected: version constraints (`jq>=1.6`).** Every executor image would need a version probe per
tool, the parse grows a comparison language, and no fault we have observed was a version fault.
Presence is the whole of the measured problem.

## 5. Scope · [S — Structure: boundary]

### In scope
- `scripts/spec-field.sh` — new, the only parser.
- `scripts/run-loop.sh` — the preflight block and the banner line.
- `specs/TEMPLATE.md`, `specs/README.md` — the grammar and the enforced/recorded distinction.

### Out of scope
- **Existing specs.** None gains a declaration in this change (§4).
- **`ralph-build.sh` / `ralph-judge.sh`.** The preflight is at the strategy layer, so a hand-run
  loop is unaffected. Pushing it into the loops would gate the judge phase on a build-phase
  concept.
- **Enforcing `Permissions:`.** Needs the container/egress mechanism. §3.2.
- **Provisioning anything.** The preflight reports what is missing. It never installs, never
  copies a config, never mutates the worktree.
- **Consumer repos.** No `notes-from-hearing` or `pi-cluster` spec is touched.

## 6. Prior decisions / facts the implementer must know · [S]

**Verified 2026-08-27 against `8fa87e3`.**

| Fact | Where | Consequence |
|---|---|---|
| the fatal preflight block already exists | `run-loop.sh:32–38` | extend it; do not add a second preflight elsewhere |
| `run-loop.sh` refuses to run on `main` | `run-loop.sh:37` | the new checks sit alongside that one, same shape |
| exit 3 already means "the container needs attention, not another retry" | `ralph-build.sh` stillborn guard | reuse it; do not invent a new code |
| `loop-doctor` detects the missing-config fault **after** the fact | `loop-doctor.sh:27,184` | this spec is the before-check for the same fault; do not change loop-doctor |
| the executor is a binding, and its config file differs per binding | `specs/20260825c-executor-binding` §3 | the `MCP:` check must derive the config path from `RALPH_EXEC_CMD`, never hardcode `opencode.json` |
| `bash 3.2` is the floor | `AGENTS.md` | no `mapfile`, no associative arrays, no `${x^^}` |
| an unquoted heredoc lets the shell expand into a foreign language | `AGENTS.md` | quote every heredoc delimiter in the new script |
| best-effort helpers may never fail the loop — **but a preflight is not a helper** | `AGENTS.md` | this one is *supposed* to be fatal; that is the point of it |

## 7. Norms · [N — Norms]

- **Absent is not empty.** A spec with no `Tools:` line declares nothing and preflights clean.
  A spec with `Tools: none` declares that it needs nothing. Both pass; they are different
  statements, and `spec-field.sh` must be able to tell them apart (exit 1 vs exit 0).
- **The preflight names the cause, never the symptom.** `missing tool 'jq' (declared in
  specs/x/spec.md)`, not `preflight failed`.
- **It reports every missing requirement, not the first.** Fixing one and rerunning to find the
  next is the loop we are removing.
- **The banner distinguishes checked from recorded.** `Permissions:` prints under a label that
  says it is not verified. Silence about that would be the whole defect this spec warns about.
- **One parser.** If a second thing needs a spec field, it calls `spec-field.sh`.

## 8. Safeguards · [S — Safeguards]

1. **A spec with no declaration behaves exactly as it does today** — same output, same exit code.
   This is the compatibility invariant and it has its own gate check with a real control.
2. **The preflight never mutates.** No install, no `cp`, no write into the worktree or the spec.
3. **Only the header region is parsed.** A `- **Tools:** …` line inside a fenced code block or
   below the first `---` is prose about the grammar, not a declaration — this document contains
   several, and a parser that reads them would fail its own spec.
4. **The `MCP:` check derives the config path from the binding.** Hardcoding `opencode.json`
   would make a codex or container run fail a check that cannot apply to it.
5. **A parse failure is never a silent pass.** An unreadable `spec.md` exits 2; it does not
   degrade to "declares nothing".
6. **Nothing outside `run-loop.sh` gains a fatal path.** A hand-run `ralph-build.sh` is unchanged.

## 9. Task breakdown · [O — Operations]

`run-loop.sh` is the script bash is *executing* when a strategy runs, so — as in
`evidence-replayable` — **the file the loop runs from is edited last** (`evidence-convention` §6b).

- **T1** — `scripts/spec-field.sh`: the grammar, header-region only, `--list`, the three exit
  codes. Nothing calls it yet.
- **T2** — document the grammar in `specs/TEMPLATE.md` and `specs/README.md`, including the
  enforced-vs-recorded table and the absent-vs-`none` distinction.
- **T3** — **last**: the preflight block and banner in `scripts/run-loop.sh`. Expect a nonzero
  exit after this task; check `bash -n` before calling it a defect, and re-invoke the loop.

## 10. Acceptance criteria (EARS) · [O]

- **AC-1** The reader shall return each comma-separated entry of a declared key on its own line,
  with surrounding whitespace stripped and empty entries dropped.
- **AC-2** Where a key is declared, the reader shall exit 0; if it is absent, then the reader
  shall exit 1 and print nothing.
- **AC-3** The reader shall parse **only** the region above the first `---` rule, and shall
  ignore any matching line inside a fenced code block.
- **AC-4** If the spec file is unreadable or an argument is missing, then the reader shall exit 2
  and print a usage line to stderr.
- **AC-5** When `--list` is given, the reader shall print every declared key, one per line.
- **AC-6** When a spec declares a tool that is not on `PATH`, `run-loop.sh` shall exit **3**
  before invoking any phase, and shall name the tool and the spec file that declared it.
- **AC-7** When several declared tools are missing, `run-loop.sh` shall name **all** of them in
  one run, not the first.
- **AC-8** Where a spec declares `Tools: none`, `run-loop.sh` shall proceed.
- **AC-9** Where a spec declares no `Tools:` key at all, `run-loop.sh` shall proceed, and its
  behaviour shall be byte-identical to `8fa87e3` for that spec.
- **AC-10** When a spec declares a non-`none` `MCP:` value and the executor's config file is
  absent from the worktree, `run-loop.sh` shall exit 3 naming that file.
- **AC-11** The `MCP:` config path shall be derived from `RALPH_EXEC_CMD`; the string
  `opencode.json` shall not appear as a literal in the preflight.
- **AC-12** `run-loop.sh` shall print declared `Permissions:` under a label stating they are
  **recorded, not verified**, and shall not fail on their content.
- **AC-13** The preflight shall not create, modify or delete any file.
- **AC-14** A `- **Tools:** …` line appearing inside a fenced code block **in this spec's own
  spec.md** shall not be read as a declaration.

## 11. Verification (the harness)

`specs/20260827a-spec-manifest/verify.sh`. Functional: it builds fixture `spec.md` files in a scratch dir
and runs the real reader and the real `run-loop.sh` against them. It never greps `run-loop.sh`
for a word — that is Trap A, and four consecutive specs shipped exactly that check.

Controls that must be asserted to **move**, per Trap B:

- **AC-6** — the positive control is a declared tool that is genuinely absent
  (`__no_such_binary_<pid>__`), asserted to produce exit 3; paired with a declared tool that is
  certainly present (`sh`), asserted to produce a *different* outcome. Without the second half,
  "exit 3" is satisfied by a preflight that rejects everything.
- **AC-9** — the compatibility control: the same spec dir run before and after, with **no**
  declaration, asserted byte-identical. This is what proves the change is additive.
- **AC-3/AC-14** — a fixture whose *body* (below `---`, and inside a fence) contains
  `- **Tools:** ghost-tool`, asserted **not** to be found. This spec's own `spec.md` is a second
  live instance of that fixture, and the gate reads it too.
- **AC-13** — checksum the fixture spec dir before and after a failing preflight, assert unchanged.

Staging: each check presence-gates on its own task's deliverable — the reader's existence for
AC-1..5, and a *behavioural* probe for AC-6..14 that pends until `run-loop.sh` actually rejects
a fixture. No check keys on a task number.

## 12. Open questions

- **OQ-1** Should `Tools:` accept a version constraint later? Rejected for now (§4) — revisit
  only when a version fault is actually observed, not before.
- **OQ-2** `Permissions:` verbs (`write:`, `exec:`, `net:`) are asserted here by convention only.
  The vocabulary should be fixed by whichever mechanism first enforces it, not invented now.
