# Spec: an attempt's record is replayable, not just readable

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor TBD)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md` (+ `/CLAUDE.md` Core Mandates)
- **Touches:** `scripts/ralph-log.sh` (new writers), `scripts/ralph-build.sh` (call sites),
  `scripts/ralph-judge.sh` (judge prompt), `scripts/loop-doctor.sh` (its artifact classifier).
  **No change** to `gate-score.sh`, `ralph-status.sh`, `ralph-retry.sh`, or any consumer repo.

---

## 1. Why · [R — Requirements]

The loop builds a prompt, hands it to a binding, and throws it away. `ralph-build.sh:136`
assembles `$prompt`, passes it as `$1` at `:152`, and nothing writes it down. It survives
only when the executor happens to echo it — `opencode` does, `codex exec` need not. **No run
in this harness can be replayed from what is on disk**, and a record that cannot reproduce
its own input is a story about the work rather than the work.

The second hole is narrower and stranger: **a passing attempt leaves almost nothing.**
`log_failure()` is reached only from the retry branch (`ralph-build.sh:233`), so the
verify output that *accepted* a change is never written anywhere, and the change itself
survives only as a commit on a branch that may be discarded. The failing attempts are
better documented than the successful ones.

This matters more than tidiness because of where the harness is going. Loop containers are
ephemeral by design; when the container exits, `.evidence/` is the only survivor. Every
gap here that is merely annoying today becomes unrecoverable the moment the process that
held the context is gone.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. Every attempt — passing or failing — persists **the exact prompt** it was given.
2. Every attempt persists **the gate's output and the gate's exit status**, on both paths.
3. A **passing** attempt persists an **applyable patch** of what it changed.
4. Every attempt persists one **`metadata.json`** carrying the attempt's own facts, using
   `loop-doctor` §3.2's vocabulary and its `null`-vs-`0` discipline.
5. A run is **addressable by a human**: `runs/<spec-slug>/latest` resolves to the newest run,
   and an operator-supplied `RUN_LABEL` travels in the record.
6. `loop-doctor` classifies every new artifact **by name**, so a healthy run reports
   `unparsed=0` exactly as it does today.
7. Nothing above can fail a loop. Every writer is best-effort.

## 3. Entities · [E — Entities]

### 3.1 The attempt artifact set

One attempt, one stem: `<task>-attempt<n>`. Extensions, all written under `$LOG_DIR`:

| artifact | when | content |
|---|---|---|
| `<stem>.prompt.md` | always, **before** the binding runs | the literal string passed as `$1`, byte for byte |
| `<stem>.log` | always | binding stdout+stderr — **unchanged** |
| `<stem>.gate.txt` | always, after verify | verify's combined output, then a `---GATE-RC---` line carrying its exit status |
| `<stem>.patch` | **pass only** | `git diff` including intent-to-added new files; `git apply`-able |
| `<stem>.diff` | **fail only** | failure forensics — **unchanged**, incl. untracked contents |
| `<stem>.json` | always, last | §3.2 |

> **`.gate.txt`, never `.gate.log`.** `loop-doctor.sh:143` and `loop-metrics.sh:36` both glob
> `T*-attempt*.log`, and `T1-attempt1.gate.log` **matches it** — one extra artifact per attempt
> would silently double every attempt count in the corpus. The extension is load-bearing.

### 3.2 `<stem>.json` — the attempt record

One JSON object, one line is not required (this file is per-attempt, not a ledger). Field
names are literal. **`null` and `0` are different values**: `0` says measured-and-zero, `null`
says not-measurable-from-what-was-available. Never collapse one into the other.

| field | type | source |
|---|---|---|
| `run_id` | string | `<agent>-<pid>`, the `$LOG_DIR` basename |
| `run_label` | string\|null | `$RUN_LABEL`; `null` when unset |
| `repo` | string | `basename $ROOT` |
| `spec` | string | `basename $SPEC_DIR` |
| `task` | string | the task label (`log_task` output) |
| `attempt` | integer | the attempt number |
| `binding` | string | `$RALPH_EXEC_CMD` verbatim |
| `agent` | string | `$RALPH_AGENT` |
| `started`, `ended` | integer | unix seconds |
| `duration_s` | integer | `ended - started` |
| `exec_rc` | integer | the binding's exit status |
| `verify_rc` | integer\|null | the gate's exit status; `null` if the gate never ran (no-op abort) |
| `outcome` | string | `passed` \| `failed` \| `noop` \| `stillborn` |
| `bytes_prompt` | integer | `wc -c` of `.prompt.md` |
| `bytes_transcript` | integer | `wc -c` of `.log` |
| `bytes_patch` | integer\|null | `wc -c` of `.patch`; `null` when no patch was written |

### 3.3 Run addressability

- **`$LOG_DIR`'s leaf stays exactly `<agent>-<pid>`.** Every reader parses the pid out of it
  (`loop-doctor` §3.1, harness README). This spec does not touch it.
- **`runs/<spec-slug>/latest`** — a relative symlink to the newest run directory, replaced on
  every `log_init`. A pointer, not a name.
- **`RUN_LABEL`** — free-text, operator-supplied, recorded in `.json`. Comparing two runs of
  one spec ("s1-run1" vs "feature-run2") becomes a query over a field, never a path to parse.

## 4. Approach · [A — Approach]

Mirror `log_failure()`, which is already the right shape: a `log_*` writer in
`ralph-log.sh` that is guarded by `LOG_OK`, swallows its own errors, and is called from one
place in `ralph-build.sh`. Four more writers in the same mould — `log_prompt`, `log_gate`,
`log_patch`, `log_meta` — plus the `latest` symlink inside the existing `log_init`.

`log_path <task> <attempt> [ext]` (`ralph-log.sh:117`) **already takes the extension**, and
already prints `/dev/null` when logging is unavailable, so callers redirect unconditionally.
No new seam is needed; this spec spends the one that exists.

The applyable patch uses `git add -A -N` (intent-to-add) before `git diff`, which is what makes
new files appear in a diff at all. It runs **before** the existing `git add -A` on the pass
path, and `-N` does not interfere with the real staging that follows.

**Rejected: a directory per attempt** (`T1-attempt1/prompt.md`, …), as the reference layout in
the source images uses. It reads better and it breaks every consumer at once — `loop-doctor`,
`loop-metrics` and `loop-index` all glob flat files, and turning a leaf into a level is exactly
the change that cost pi-cluster #197 and #198. Extensions buy the same content for no migration.

**Rejected: deriving the patch from the commit** (`git show <sha>`). True while the branch
lives; a discarded worktree takes it with it, and the record is supposed to outlive the run.

## 5. Scope · [S — Structure: boundary]

### In scope
- `scripts/ralph-log.sh` — four new writers, `latest` symlink in `log_init`.
- `scripts/ralph-build.sh` — the call sites, and nothing else about the loop.
- `scripts/ralph-judge.sh` — persist the judge prompt via the same writer.
- `scripts/loop-doctor.sh` — teach its `case` the new extensions.

### Out of scope
- **The retry contract, task selection, gate semantics, commit shape.** Where the record goes,
  not what the loop does.
- **`gate-score.sh`.** `.gate.txt` records the gate's own output and rc. Wiring a *score* into
  the build phase is judge-loop OQ-5 and stays deferred.
- **`loop-index.py` / `metrics.jsonl`.** They derive from what exists; adding fields to the
  derived layer is a separate change with its own readers.
- **Any consumer repo.** No `.evidence/` in `notes-from-hearing` or `pi-cluster` is migrated;
  old runs keep the old shape and must stay readable.
- **Deleting `log_failure`'s untracked-contents block.** It captures content that a `.patch`
  from a *failed, reset* tree cannot, and it was added for a reason (2026-08-25, `asset-ladder`).

## 6. Prior decisions / facts the implementer must know · [S]

**Verified 2026-08-26 against `1ea0c6e`.**

| Fact | Where | Consequence |
|---|---|---|
| `log_path <task> <attempt> [ext]` already exists and defaults `ext` to `log` | `ralph-log.sh:117` | pass an extension; do **not** build paths by hand |
| `log_path` prints `/dev/null` when `LOG_OK != 1` | `ralph-log.sh:119` | writers may redirect unconditionally |
| `log_failure` is called **only** on the retry path | `ralph-build.sh:233` | the pass path currently records nothing but a commit |
| the gate output is already captured in `$out` | `ralph-build.sh:189` | `.gate.txt` needs no second gate run — **never re-run `verify.sh`** |
| `git add -A` runs at the top of the pass branch | `ralph-build.sh:192` | the patch must be written **before** it |
| `loop-doctor` globs `T*-attempt*.log` and counts everything else as `unparsed` | `loop-doctor.sh:143,150` | `.gate.log` would inflate `attempts`; **all four** new extensions need a `case` arm or every healthy run reports drift |
| `loop-metrics.sh` globs `$TASK-attempt*.log` | `loop-metrics.sh:36,41,85` | same hazard, second reader |
| helpers must never fail the loop they report on | `AGENTS.md` — "best-effort helpers stay best-effort" | every write guarded, every call `|| true` |
| bash 3.2 is the floor; `stat -f` means *filesystem* on Linux | `AGENTS.md` — portability | use `wc -c` for size; no `mapfile`, no `${x^^}` |
| an unquoted heredoc lets the shell expand into a foreign language | `AGENTS.md` | if JSON is emitted via `jq -n`, pass values with `--arg`, never interpolate |
| `executor-binding` AC-7's shrink rule was **scoped to that change** by #201 | `executor-binding` §10 AC-7 note | this spec inherits **no** line-count ratchet; a ratchet against an absolute number "fires at strangers" |

## 7. Norms · [N — Norms]

- **Naming:** writers are `log_<noun>`, matching `log_failure`/`log_where`. Artifacts are
  `<stem>.<ext>` with the stem produced by `log_path`, never string-built.
- **Observability:** a writer that cannot write says so **once on stderr** and continues —
  a silent helper is one nobody notices is broken (`AGENTS.md`).
- **Error handling:** `{ … } > "$f" 2>/dev/null || true`, the `log_failure` pattern verbatim.
- **Ordering:** `.prompt.md` is written **before** the binding is invoked, so a stillborn
  executor still leaves the input that killed it. `.json` is written **last**, so it can
  measure the others.
- **The record is bounded.** `.prompt.md` is small by construction; `.patch` inherits
  `log_failure`'s 64 KiB-per-file discipline for anything it inlines.

## 8. Safeguards · [S — Safeguards]

1. **No writer may fail a run.** A read-only mount, a full disk, or an absent `$LOG_DIR`
   changes the loop's exit status by zero.
2. **`verify.sh` is run exactly as often as it is today.** `.gate.txt` is written from the
   already-captured `$out`. A second invocation would double every gate's side effects and
   is the one unrecoverable mistake in this spec.
3. **`.evidence/` never enters a patch.** `git add -A -N` and `git diff` are both scoped with
   `-- . ':!.evidence'`, as `ralph-build.sh:180`'s no-op check already is.
4. **`git add -A -N` must not disturb the commit that follows.** Intent-to-add only.
5. **The run-dir leaf stays `<agent>-<pid>`.** No label, no slug, no timestamp folded in.
6. **`latest` is a relative symlink inside its own `runs/<spec-slug>/`** — an absolute one
   breaks the moment a repo is cloned elsewhere, which is the ephemeral-container case.
7. **Old runs stay readable.** Every reader change is additive; a run directory holding only
   `.log` and `.diff` classifies exactly as it does today.

## 9. Task breakdown · [O — Operations]

**Ordering is load-bearing, and it is not the order of §3.1.** `scripts/ralph-log.sh` is
*sourced* at loop startup (`ralph-build.sh:99`), so editing it mid-run cannot disturb the
running process — its functions are already resolved. `scripts/ralph-build.sh` is the script
bash is *executing*, and bash reads a running script by byte offset: rewriting it mid-run
leaves the shell reading the new file from an offset that lands mid-token
(`evidence-convention` §6b, observed 2026-08-24). So **every writer lands first, and all the
call sites land last, in one task.**

- **T1** — `log_prompt` in `ralph-log.sh`.
- **T2** — `log_gate` in `ralph-log.sh`, writing `.gate.txt` (never `.gate.log`).
- **T3** — `log_patch` in `ralph-log.sh`, via `git add -A -N` then `git diff`.
- **T4** — `log_meta` in `ralph-log.sh`, emitted with `jq -n --arg`.
- **T5** — the relative `latest` symlink and `RUN_LABEL`, in `log_init`.
- **T6** — `loop-doctor.sh`'s artifact `case`, so a healthy run still reports `unparsed=0`.
- **T7** — **last**: every call site in `ralph-build.sh` and `ralph-judge.sh`. A nonzero exit
  after this task is expected; check `bash -n` before calling it a defect, and **re-invoke**
  the loop rather than resuming it.

## 10. Acceptance criteria (EARS) · [O]

- **AC-1** When the build loop invokes an executor binding, the harness shall have already
  written `<stem>.prompt.md` containing the prompt byte-for-byte.
- **AC-2** If the executor is stillborn and the run aborts, then `<stem>.prompt.md` shall
  still exist.
- **AC-3** When the gate runs, the harness shall write `<stem>.gate.txt` containing the gate's
  combined output followed by a line matching `^---GATE-RC---$` and then the gate's exit status
  — on the passing path and the failing path alike.
- **AC-4** The harness shall invoke `verify.sh` exactly as many times per attempt as it did at
  `1ea0c6e` — writing `.gate.txt` shall not re-run the gate.
- **AC-5** When an attempt passes, the harness shall write `<stem>.patch` such that
  `git apply --check` accepts it against the pre-attempt tree, **including files the attempt
  newly created**.
- **AC-6** The harness shall exclude every path under `.evidence/` from `<stem>.patch`.
- **AC-7** When an attempt ends by any path, the harness shall write `<stem>.json` matching
  §3.2, in which an unmeasurable field is `null` and a measured-zero field is `0`.
- **AC-8** Where `RUN_LABEL` is unset, `<stem>.json`'s `run_label` shall be `null` — never the
  empty string and never absent.
- **AC-9** The harness shall maintain `runs/<spec-slug>/latest` as a **relative** symlink to
  the most recently initialised run directory.
- **AC-10** The run directory's basename shall remain exactly `<agent>-<pid>`.
- **AC-11** If any artifact write fails, then the loop's exit status shall be unchanged, and
  the failure shall be reported once on stderr.
- **AC-12** When `loop-doctor` reads a run directory containing the full §3.1 artifact set, it
  shall report `unparsed` **0** and an `attempts` count equal to the number of `.log`
  transcripts — not the number of files.
- **AC-13** When `loop-doctor` reads a **pre-existing** run directory holding only `.log` and
  `.diff` files, its output shall be byte-identical to its output at `1ea0c6e`.
- **AC-14** No new artifact's filename shall match the glob `T*-attempt*.log`.
- **AC-15** When the judge loop invokes `JUDGE_CMD`, the harness shall persist that prompt by
  the same writer and naming convention as the build loop.

## 11. Verification (the harness)

`specs/evidence-replayable/verify.sh`. **Functional, not grep-based** — `ralph-log.sh` is
sourceable, so the gate sources it, points `LOG_DIR` at a scratch dir and `ROOT` at a fixture
git repo, calls each writer, and asserts on the artifacts. A check that greps the loop for the
word `prompt.md` would pass on a comment (`TEMPLATE.md` §11, Trap A).

Positive controls are mandatory, per Trap B:

- **AC-5** — the fixture must contain a **new, untracked** file, and the gate must show
  `git apply --check` *rejecting* a patch built without `-N` before accepting the one built
  with it. Otherwise "the patch applies" is satisfied by an empty patch.
- **AC-12/AC-13** — two fixture run directories: one full modern set, one legacy `.log`+`.diff`
  pair. The legacy one is the positive control that the reader change is additive.
- **AC-14** — assert by *expansion*, not by reading the source: expand `T*-attempt*.log` over
  the modern fixture and assert the count equals the transcript count.
- **AC-4** — the fixture `verify.sh` appends a byte to a counter file on each invocation; the
  gate asserts the counter reads exactly what it read at `1ea0c6e`.
- **AC-11** — `chmod 000` the scratch log dir, call every writer, assert exit status 0.

Staging: every check presence-gates on **its own** artifact (`[ -f "$d/T1-attempt1.prompt.md" ]`
→ assert, else `pend`), never on a task number, and never on the run directory above it — a
directory created by T1 would arm T3's checks and fail them on work not yet due.

## 12. Open questions

- **OQ-1** Should `.gate.txt` also carry the `---GATE-SCORE---` block when `gate-score.sh`
  happens to be what ran? Deferred: judge-loop OQ-5 owns wiring the score into the build
  phase, and answering it here would smuggle that change in under a logging spec.
- **OQ-2** `RUN_LABEL` is free text. Does anything downstream need it constrained to a slug?
  Nothing consumes it yet; leave it free until a consumer asks.
