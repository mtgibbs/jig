# Spec: the index can see a run that lives one level deeper

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, python3
- **MCP:** none
- **Permissions:** write:scripts/loop-index.py, write:specs/20260825b-evidence-spec-nesting/**, exec:git
- **Touches:** `scripts/loop-index.py` (`harness_roots`), the empty-directory prunes in
  `scripts/ralph-log.sh` and `scripts/ralph-status.sh`, and the depth assumption in
  `specs/20260825b-evidence-spec-nesting/verify.sh` (§5). **No change** to `loop-doctor.sh`,
  `ralph-build.sh`, or any other spec.

---

## 1. Why · [R — Requirements]

`specs/20260827b-fleet-run-key` inserted a `<host>` level so two workers sharing a pid cannot
collide: runs moved from `.evidence/runs/<slug>/<agent>-<pid>` to
`.evidence/runs/<slug>/<host>/<agent>-<pid>`. That spec's T5 said to teach **both** readers the
new level — `loop-doctor.sh` and `loop-index.py`. Its gate asserted only `loop-doctor`, so only
`loop-doctor` was taught, and the gate passed with half the task undone.

**`loop-index.py` has been blind to every run since that merge.** Bisected: the
`20260825b-evidence-spec-nesting` gate was green at `05ee8d7` and red from the `fleet-run-key`
merge onward, failing `AC-4`, `AC-8` and `AC-9` — the index recovers no pid, sees no codex run,
and never names a real run directory. The corpus the judge and `token-bench` read has been
missing runs for a day.

Nothing errored. An index that enumerates nothing looks exactly like an index of a repo that has
not run anything.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A run at `.evidence/runs/<slug>/<host>/<agent>-<pid>` is enumerated by `loop-index.py`.
2. Its status JSON at `.evidence/status/<slug>/<host>/<agent>-<pid>.json` is joined to it.
3. A run at the **one-level** layout `<slug>/<agent>-<pid>` still enumerates — unchanged.
4. A run in the **flat** layout `<agent>-<pid>` still enumerates — unchanged.
5. The scope reported for a nested run is the **spec slug**, not the host.
6. A host directory is never itself counted as a run.
7. A run in the **older** `<slug>/<agent>-<pid>` layout is still reaped when it ages out — the
   reap was moved to the new depth, not widened, so those corpora stopped being collected.
8. A wholly-expired spec leaves **no empty husk**: neither an empty host directory nor the
   empty slug directory above it survives the sweep, in either store.
9. `specs/20260825b-evidence-spec-nesting`'s gate is green again.

Outcomes 3 and 4 are the controls. Two older layouts exist in real corpora on disk, and a fix that
sees the new one by ceasing to see the old ones has moved the blindness rather than cured it.

## 3. Entities · [E — Entities]

### 3.1 The three layouts, all live at once

| layout | shape | written by |
|---|---|---|
| flat | `runs/<agent>-<pid>/` | the original loop |
| scoped | `runs/<slug>/<agent>-<pid>/` | pi-cluster#194, the spec-slug level |
| **nested** | `runs/<slug>/<host>/<agent>-<pid>/` | `20260827b-fleet-run-key` |

`.evidence/status/` mirrors each shape exactly, with `<agent>-<pid>.json` in place of the run
directory.

### 3.2 `harness_roots(base, leaf_globs)` — the one seam

It already returns `[(path, scope_or_None)]` for the flat and scoped layouts, and **both stores go
through it**: `load_status` calls it with `"*.json"`, the log walk calls it with `RUN_GLOBS`. One
change there fixes runs and status together. Nothing else in the file needs to learn about hosts.

`scope` keeps its current meaning — "the thing the runs below it have in common", which for a
nested run is the **spec slug**, the level a reader recognises. The host is below it and is not
the scope.

## 4. Approach · [A — Approach]

Descend one level further in `harness_roots`, and only where a scope directory does not itself
hold runs. Same shape as the existing loop, one level deeper.

**Rejected: changing `glob_runs` to glob `*/<agent>-*`.** It would find nested run directories and
would not fix `load_status`, which never calls `glob_runs` — status would stay blind, and outcome
2 would fail while outcome 1 passed. The seam is `harness_roots` precisely because both stores
already share it.

**Rejected: teaching the readers to recognise a host by name.** `loop-doctor`'s run-id glob
already matches a Kubernetes pod name like `harness-run-7`, which is why
`20260827b-fleet-run-key` excludes the host level **by position**. A name test would be wrong for
the same reason here.

## 5. Why this touches another spec's gate · [S — Scope]

`specs/20260825b-evidence-spec-nesting/verify.sh` finds run directories with
`find -mindepth 2 -maxdepth 2`, so a run at depth 3 is invisible to it and it reports "no run
directory was created at all" — a true statement about what it looked at, and a misleading one
about the tree.

That gate is this regression's **detector**: it is what caught a bug two merges old. It is fixed
here rather than left broken, because a detector that cannot see the layout it guards is worse
than no detector — it reports a fault in the wrong place. `-mindepth 2` stays, so the "still flat
in the root" case it exists to catch is still caught.


## 6. The blast radius was three deep, not one · [A — Approach]

`20260827b-fleet-run-key` inserted one directory level, and three separate readers/writers had the
old depth baked in. Two were found only by running **every** gate rather than the ones that looked
relevant:

| symptom | found by |
|---|---|
| `loop-index.py` enumerates nothing | `evidence-spec-nesting` AC-4/8/9, two merges later |
| that gate's own `-maxdepth 2` | reading it, once it was the accused |
| empty spec directories never pruned | `evidence-spec-nesting` AC-6, only after the first two were fixed |

The third was invisible until the first two were repaired — a gate reports its first failure, and
the ones behind it wait their turn. That is an argument for fixing a regression completely and
re-running, rather than declaring victory when the symptom that started the investigation clears.
