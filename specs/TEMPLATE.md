# Spec: <Feature Name>

<!--
  Copy this file to specs/<feature>/spec.md and fill it in. Delete the HTML
  comments as you go — they're guidance, not part of the spec.

  The golden rule, learned the hard way (see homepage-refresh §11): the model
  nails anything backed by a concrete pattern, a literal value, or a testable
  rule — and guesses wherever you left intent as prose. SPECIFICITY IS THE LEVER.
-->

> **This template is our REASONS Canvas.** It overlays Martin Fowler's SPDD seven
> dimensions — **R**equirements · **E**ntities · **A**pproach · **S**tructure ·
> **O**perations · **N**orms · **S**afeguards — onto our EARS + `verify.sh` discipline.
> Each section is tagged with its REASONS letter. Sections are ordered
> *constraints-before-work* (best for a literal executor like qwen), not in canvas
> letter-order; all seven dimensions are present. Norms (§7) + Safeguards (§8) are the
> SPDD additions vs our old template — the cross-cutting + non-negotiable layers where
> an executor otherwise guesses badly. Rationale: `pi-cluster/docs/research/local-coding-agent-sdd.md` §11.

- **Status:** Draft v0.1   <!-- Draft -> Planned (OQs resolved) -> In progress -> Done; bump version on tuning -->
- **Owner:** <name>
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** <the files/paths this will change>
- **Tools:** <comma-separated executables needed on PATH>   <!-- e.g. git, jq, swift -->
- **MCP:** <comma-separated MCP server names>   <!-- e.g. homelab, memory; none if none required -->
- **Permissions:** <comma-separated permission declarations>   <!-- e.g. write:scripts/**, exec:git, net:api.github.com; NOTE: unenforced until container/egress exists -->

---

## 3.2 The three fields, and their very different weights

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

### Absent vs explicit `none`

An **absent** key and an **explicit** `none` are different:

- **Absent:** the key does not appear in the header block. This means "declares nothing", never "declares none".
- **Explicit `none`:** the key appears with value `none`. This means "declares empty" (e.g. `Tools: none` means no tools required).

Both pass preflight; they are different statements.

## 1. Why · [R — Requirements]
<!-- The problem, in 2-4 sentences. Stops the agent optimizing the wrong thing. -->

## 2. Outcomes (Definition of Done) · [R — Requirements]
<!-- Done-in-plain-language. The human-alignment layer. Numbered, observable. -->

## 3. Entities · [E — Entities]
<!-- The domain objects this touches and their SHAPE — tables/columns, message/payload
     fields, config keys, CRDs, state machines, relationships. Use literal field names and
     types (e.g. `intake_items(id, due_at TIMESTAMPTZ, student ENUM ronin|rory|both|unknown)`).
     A literal executor invents field names and shapes unless you pin them here.
     If the work is genuinely stateless (pure UI/script with no data model), say so and skip. -->

## 4. Approach · [A — Approach]
<!-- The strategy in 2-5 sentences: HOW we intend to meet §1, and crucially WHICH existing
     pattern this mirrors ("same shape as X in path/to/file"). The high-level plan that the
     §9 task breakdown then makes concrete. Note any approach considered and rejected (so a
     later reader — or a regenerating model — doesn't re-litigate it). Rejected approaches
     often live in past agent sessions, not docs — the lifecycle's ctx prior-art pass
     (`ctx search "<terms>"`) is where to dig them up. -->

## 5. Scope · [S — Structure: boundary]
### In scope
<!-- Exact files/areas. -->
### Out of scope
<!-- What NOT to touch. This list prevents drift as much as the "in" list. Be explicit
     about anything adjacent the model might "helpfully" change. -->

## 6. Prior decisions / facts the implementer must know · [S — Structure: system fit & deps]
<!-- The context dump that prevents hallucination. Include:
     - exact resource names, URLs, ports, namespaces (look them up — don't make the model guess)
     - which EXISTING pattern to copy, and the file it lives in ("like X in path/to/file")
     - OPERATIONAL REALITY the model can't infer from code (e.g. "service X is deployed but unused")
     - upstream/downstream dependencies and how this component fits the system
     - literal values for anything linkable (URLs, UIDs)
     - decisions/attempts from prior agent sessions (`ctx search --file <path>` per touched
       file) — distill the finding into a sentence here; cite the ctx session id so a
       reviewer can pull the full context with `ctx show session <id>` -->

## 7. Norms · [N — Norms]
<!-- Cross-cutting STANDARDS for this task — the stuff a literal executor has no taste for and
     will guess (badly) unless stated. Pull the relevant rules from `specs/design-principles.md`
     and make them concrete here:
       - Naming: file/var/resource conventions to follow.
       - Observability: what to log/emit; existing metric/label conventions to match.
       - Error handling / defensive coding: how failures surface; what's continueOnError.
       - House style / taste: e.g. "distinct icons per metric — do NOT reuse one for three"
         (the literal homepage-refresh failure). Specify, or it recurs.
     Norms are how the work should look; Safeguards (§8) are what it must never violate. -->

## 8. Safeguards · [S — Safeguards]
<!-- NON-NEGOTIABLE boundaries and invariants — distinct from "out of scope" (what to leave
     alone). These are what must ALWAYS hold, stated so a passing §11 gate can't be "confidently
     wrong":
       - Security: no inline secrets; secrets via ExternalSecret only; never echo a secret;
         never execute downloaded/untrusted files.
       - Data invariants: idempotency / dedup key; no destructive writes without X; PK/uniqueness.
       - Performance/resource bounds: limits, timeouts, payload caps.
       - Safety: what a wrong implementation could break, and the guardrail against it.
     Where possible, each safeguard should map to a §11 verify.sh assertion. -->

## 9. Task breakdown · [O — Operations]
<!-- Ordered work units. Mark which can run in parallel. Map to files where possible.
     Obey §7 Norms and §8 Safeguards throughout — they are always-on, not a final step. -->

## 10. Acceptance criteria (EARS) · [O — Operations made testable]
<!-- The testable contract — the HEART of the spec. Use the five EARS patterns:
       Ubiquitous:  The <system> shall <response>.
       Event-driven: When <trigger>, the <system> shall <response>.
       State-driven: While <state>, the <system> shall <response>.
       Unwanted:    If <condition>, then the <system> shall <response>.
       Optional:    Where <feature>, the <system> shall <response>.
     Each one must be checkable by the verification harness in §11. If you can't test it,
     rewrite it until you can. Include the "what if a thing is missing" cases.
     (This is SPDD's "Operations" dimension — but compiled to a deterministic gate, not prose.) -->

## 11. Verification (the harness) — SHIP A `verify.sh`
<!-- §10 acceptance criteria, COMPILED into a runnable, deterministic gate: a `verify.sh`
      in the spec dir that exits 0 only if the work is acceptable. Mandatory for any spec
      handed to an agent loop. Two tiers:
        - STATIC (no deploy): lint, build/dry-run, structural/semantic greps. This is what
          gates each loop iteration — must be deterministic + offline.
        - LIVE (post-deploy): renders-with-data, secrets-synced, health. Human/Flux; NOT
          gated in the loop.
      The LOOP runs verify.sh — the model NEVER self-certifies "done". Write each §10
      criterion (and each §8 safeguard) so it maps to a verify.sh assertion.
      (Hashimoto harness-engineering / TDD-for-agents.) -->

### The gate layout — per task, since 20260828i

**A multi-task spec carries one gate per task**: `tasks/T<NN>-<slug>/verify.sh`, one
directory per `tasks.txt` line, in order (`specs/20260828i-per-task-gates`; enforced —
`ralph-build.sh` refuses a multi-task spec without a `tasks/` directory unless
`RALPH_ALLOW_MONOLITHIC=1` marks a legacy re-run). The rules:

  - After task N the loop runs the gates for tasks **1..N** — cumulative, so a later task
    that breaks an earlier one still fails, while nothing beyond N is ever consulted.
  - A task gate asserts ONLY its own task's criteria. **`pend` is banned from task
    gates** — there is nothing to defer, because later tasks' criteria are simply not
    there. This is the point: the old whole-spec pend-staged gate was THE ROADMAP — an
    executor that ran it read `pend acN (not built yet)` as a to-do and did a later
    task's work early (20260828i defect 2; re-proved twice on 20260831a, 2026-08-31 —
    `docs/runs/2026-08-31-the-watched-run.md`).
  - The spec-level `verify.sh` holds ONLY convergence assertions — integration and
    end-state — and runs once, at the end, under `STRICT=1`. No pend there either: at
    convergence "not built yet" is a failure by definition.
  - Every task-gate assertion is named by at least one mutant, and `verify.sh --self-test`
    must kill them all (20260828i outcomes 5–6): an assertion no mutant can trip has never
    been observed to work.
  - Source `specs/lib/assert.sh` for the vocabulary; see any of
    `specs/20260828k..20260830b` for the worked shape.

A bonus the layout buys: skip-satisfied (`ralph-build.sh`, 20260828l) runs task N's own
gate before dispatching it — so if an earlier task overshot and already did the work, task
N is skipped gracefully instead of dying as an unwinnable no-op.

**A task may declare its scope** (20260831d, opt-in): `tasks/T<NN>-<slug>/scope`, one git
pathspec glob per line, repo-relative (`#` comments and blanks ignored). The loop states
the globs in the executor's prompt, and an attempt that changes any path outside them is
rejected before the gate runs — wholesale, with the tree reset; in-scope work in the same
attempt is discarded too, because filtering the commit could bless a gate that went green
on out-of-scope files. A scope file with no globs is refused up front. No scope file, no
change in behavior. Declare a scope when a task's deliverables are exactly enumerable
(most are); it is the guard that keeps `add -A` from attributing stray work to the wrong
task.

**A single-task spec** needs no `tasks/` directory: one spec-level `verify.sh`, no `pend`
anywhere (with one task there is no later work to defer to).

**Legacy note:** specs written before 20260828i use a whole-spec three-verdict
(`ok`/`no`/`pend`) gate run after every task, with `STRICT=1` promoting `pend` to FAIL at
the end. Read 20260828i for that contract when maintaining an old gate. Do not author new
ones — the shape is deprecated, and the loop will refuse it.

### Task granularity, and what a task's section may hold

  - Tasks share a spec when they share a gate and a design; anything else is either the
    same task or a different spec (ratified 2026-08-31, after a docs-only task rode along
    with a behavior task for no reason but habit).
  - **A task's anchor section holds nothing but that task's own deliverables** (20260831a
    Tuning log): the task line anchors harder than the spec, and a section carrying two
    tasks' payloads gets both implemented by whichever task cites it first.
  - Keep task lines SEMANTICALLY RICH. Measured on the model-watch dogfood —
    "write model-watch.py: the sweep, the gate logic, the DRY_RUN output contract"
    scored 17/19 first try, while "implement the whole model-watch feature" made the
    model build something suggested by the NAME (a filesystem poller) and scored 7/19.
    A vague line lets the work drift to the noun.

<!-- A CHECK MUST TELL ITS SIGNAL FROM WHAT WOULD BE TRUE ANYWAY.
     This is the corollary of the amendment "Gates must prove they can fail", applied to the
     one place it keeps being violated: the search a check performs. FOUR times in four
     consecutive specs, a check passed while the feature was absent — every one of them
     written by someone who had read that amendment.

       spec                   check                          why it passed with NO feature
       ---------------------  -----------------------------  ------------------------------------
       loop-doctor            ac15:no-forbidden-invocations  matched the word in a COMMENT
       ralph-retry-contract   ac9:regressed-check-named      FAIL feedback already said the name
       run-regression-guard   ac9:stop-names-destroying-task task banner already said the label
       tasks-ledger           ac6:resume-skips-proven-tasks  probe never matched, so "0" was free

     TRAP A — THE NEEDLE IS ALREADY IN THE HAYSTACK. The thing you grep for exists for reasons
     that have nothing to do with the feature: a comment, a doc block, the prompt you are
     inspecting, a banner the loop prints for every task. Searching the WHOLE artifact for a
     word the artifact already contains is not a check, it is a coin that lands heads.
       Fix: scope the search to the REGION THE FEATURE PRODUCES, and strip comments first.
         grep -q "$name" "$log"                        # lies
         sed -n "/^REGRESSION/,/^\$/p" "$log" | grep -q "$name"   # checks

     TRAP B — AN ABSENCE ASSERTION SATISFIED BY A BROKEN PROBE. A check of the form "expect
     zero / expect absent" is ALSO satisfied when the measurement itself is broken — a grep
     with a wrong anchor, a counter reading a file that was never written, a command whose
     output format moved. The check and the bug produce identical output.
       Fix: every absence assertion needs a POSITIVE CONTROL — show the probe returning a
       NON-zero / present result in a case you construct on purpose. If you cannot make the
       probe fire, you have not proven absence; you have proven nothing.

     TRAP A-PRIME — THE SCOPE THAT SILENTLY DID NOTHING. Trap A's fix is "scope the search".
     But a scope can be WRITTEN and be INERT, and an inert scope looks exactly like a working
     one. Found in specs/harness-egress-allowlist 2026-08-18 (#184), where the file collection
     read:
         grep -rl -- "coding-harness" "$R" --include='*.yml' --include='*.yaml'
     `--` terminates option parsing, so every --include= after it was consumed as a FILENAME and
     the filters did nothing at all. The collection was pulling *.md, *.sh, *.json and *.txt,
     which meant `incompose 'harness-egress'` could be satisfied by a SPEC DOCUMENT that merely
     mentions the service — AC1/AC2/AC3 passing on a task that wrote only prose. A gate
     satisfiable by its own spec. Caught latent, before it ever fired, only because the work is
     unbuilt and the spec lives in the other repo.
       Note what does NOT catch this. The one-question test above passes cleanly: "it fails when
     no compose file declares harness-egress" is a correct sentence about a broken check. The
     scope was not missing, so reviewing for Trap A finds nothing either. Only the NEAR-MISS
     practice below catches it — a fixture that mentions the service in prose without declaring
     it exposes the false PASS on the first run.
       Fix: prove the scope excluded something. If a filter is load-bearing, assert the
     collection is non-degenerate rather than trusting that the flag took effect.

     THE ONE-QUESTION TEST, before writing any check:
       "Name the concrete condition under which this check FAILS."
     If you cannot state it in one sentence, or if the condition you name is also what happens
     when your measurement breaks, it is not a check yet.

     AND THE PRACTICE THAT ACTUALLY CATCHES THESE: run the gate against a NEAR-MISS, not only
     against an empty tree. An empty tree proves a gate PENDS; a near-miss proves it
     DISCRIMINATES. Write a complete, plausible implementation with exactly one thing wrong,
     in a scratch dir, uncommitted. specs/20260818d-tasks-ledger did this — an ancestry-only build passed
     25 of 28 checks and failed precisely the two written to catch it, and the experiment
     surfaced three gate defects that clean main could never have shown (see that spec's
     evidence/). Keep the adversary OUT of the repo, or a later loop run stops being a fair
     measurement. -->

## 11b. Loop execution (handing to a local model)
<!-- Local models (qwen) are faithful literal executors with no stamina/taste/self-check.
     Run via scripts/ralph-build.sh: ONE task per iteration, FRESH context each time,
     timeboxed (watchdog), gated on verify.sh, retry-with-feedback, stop-for-human when
     stuck. Decompose §9 into a tasks.txt. Bound scope = small context = reliable. Never
     hand the model the whole repo or whole spec at once. -->

## 12. Open questions
<!-- Honest unknowns. Don't fabricate — flag them, resolve in the Plan phase, then fold
     the answers back in (living document). Number them OQ1, OQ2, ... -->

<!-- ## 13. Plan — implementation reference   (added when OQs are resolved) -->
<!-- ## 14. Tuning log                          (added after an agent eval — what missed and why) -->

## Two-way sync rule (keep spec ⇄ code aligned)
<!-- From SPDD, and our own drift finding (#7): the spec is the source of intent, so —
       - LOGIC change (behavior differs): fix the SPEC first, then regenerate/edit code.
       - REFACTOR (no behavior change): change code, then sync the fact back into the spec.
       - HOTFIX that bypassed the loop: post-mortem it back into the spec + Tuning log (§14).
     A taste/Norms correction made in review (§7) MUST be written back, or the executor
     reproduces the same miss next iteration. "When reality diverges, fix the prompt first." -->

## Worked-example checklist (before you hand this to an agent)
<!-- - [ ] ctx prior-art pass run (feature terms + each touched file); findings folded into §4/§6.
     - [ ] Every linkable target is a LITERAL url/uid, not prose.
     - [ ] §3 Entities pin literal field names/types (or "stateless — n/a").
     - [ ] §4 Approach names the existing pattern being mirrored.
     - [ ] §7 Norms pull the taste/observability rules that apply (don't leave to guess).
     - [ ] §8 Safeguards state the non-negotiables, and each maps to a §11 assertion where possible.
     - [ ] Novel/unfamiliar patterns have a copy-paste example block.
     - [ ] Where an existing-but-different pattern could mislead, the contrast is called out.
     - [ ] Operational facts the model can't infer are stated in §6.
     - [ ] Every §10 criterion is testable by §11. -->
