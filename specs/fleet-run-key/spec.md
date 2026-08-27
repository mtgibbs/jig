# Spec: a run key that survives two workers

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, jq, sed
- **MCP:** none
- **Permissions:** write:scripts/**, write:specs/fleet-run-key/**, exec:git
- **Touches:** `scripts/run-key.sh` (new), `scripts/ralph-log.sh` (`log_init`, the GC),
  `scripts/ralph-status.sh` (`hb_write` root), `scripts/loop-doctor.sh` and
  `scripts/loop-index.py` (the readers). **No change** to `ralph-build.sh`, `ralph-judge.sh`,
  `run-loop.sh`, `gate-score.sh`, or to any spec's `verify.sh`.

---

## 1. Why · [R — Requirements]

`ralph-log.sh:80` names every run `<agent>-$$`. A pid is unique **within one PID namespace**,
and `docs/design/fleet-dispatch.md` §6 names the consequence: two workers on two nodes collide
silently and corrupt the corpus.

Measured on this container, the real bound is tighter than "two nodes". `/proc/1/cmdline` is
`tini`, so a loop container has its **own** PID namespace and its pids start at 1. Two loop
containers **on the same node** can therefore both produce `qwen-1234`. Fan-out does not need two
machines to collide; it needs two containers, which is the entire premise of the fleet.

The collision is silent in the worst way. Nothing errors: the second run writes its attempts into
the first run's directory, `loop-doctor` reads one run with double the attempts, and the corpus
that `token-bench` and the judge draw on is quietly wrong. There is no failure to notice, only a
number that was never true.

This is the fence at the top of the cliff, and it must land **before** the first concurrent
fan-out (fleet-dispatch §Sequencing item 1), not after — because a corrupted corpus cannot be
distinguished from a real result afterwards.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. Two runs that share a pid but differ in host **cannot** write to the same run directory.
2. The run directory's **leaf is still exactly `<agent>-<pid>`** — every reader parses the pid out
   of it, and `specs/evidence-replayable` AC-10 asserts it. This spec does not get to change that.
3. `latest` keeps working exactly as `specs/evidence-replayable` AC-9 specifies: a slash-free
   relative symlink beside the run directory.
4. The status file cannot collide either — it has the same defect and the same fix.
5. Every attempt record carries the **host** and a globally unique **`run_key`**.
6. `loop-doctor` reports a healthy run exactly as it does today: `unparsed=0`, and the run count
   unchanged. A host directory is **not** a run.
7. The evidence GC still reaps run directories, and never reaps a host directory.
8. Nothing above can fail a loop. Every writer stays best-effort.

## 3. Entities · [E — Entities]

### 3.1 The host discriminator

Resolved by `scripts/run-key.sh`, in this order, first non-empty wins:

| source | why |
|---|---|
| `$RALPH_HOST_ID` | operator override; the dispatcher will set it to the Job/pod name |
| `hostname` | in a container this is the container ID; in a k8s Job, the pod name |
| `unknown` | never empty, never fatal |

Sanitised to `[A-Za-z0-9._-]`; every other byte becomes `_`. It is a **directory name**, so a dash
is fine here — and that is exactly why the discriminator does not go in the leaf (§4).

### 3.2 The layout

```
.evidence/runs/<spec-slug>/<host>/<agent>-<pid>/     ← run artifacts
.evidence/runs/<spec-slug>/<host>/latest             ← symlink -> <agent>-<pid>
.evidence/status/<spec-slug>/<host>/<agent>-<pid>.json
```

One new level, `<host>`, between the spec slug and the run. Nothing below it changes.

### 3.3 New record fields

Added to the per-attempt `<stem>.json` of `specs/evidence-replayable` §3.2. Both are **strings**,
never null — the resolver always yields a value:

| field | value |
|---|---|
| `host` | the §3.1 discriminator |
| `run_key` | `<host>/<agent>-<pid>` — globally unique, and a real relative path under the spec slug |

`run_id` keeps its current meaning (the leaf) and its current value. It is host-local, and it is
what the existing readers join on; `run_key` is the fleet-wide identity. Both, not one.

## 4. Approach · [A — Approach]

Put the discriminator in a **directory level**, not in the run-dir name. Same shape as the
`<spec-slug>` level that `log_init` already inserts — this is one more of those, not a new
mechanism.

**Rejected: encoding the host in the leaf** (`<agent>-<host>-<pid>`, `<agent>-<pid>.<host>`, or a
compound pid token). It reads as the obvious fix and it breaks four things at once.
`loop-index.py:335` does `name.split("-", 1)` and its comment states the invariant it relies on —
"the agent never contains one, and a pid never does either". A k8s pod name (`harness-run-7`) is
full of dashes. `specs/evidence-replayable` AC-10 asserts the leaf matches `<agent>-<pid>`, and
`ralph-status.sh:123` emits `"pid":%s` **unquoted**, so a non-numeric pid component produces
invalid JSON. The directory level costs one `mkdir` and breaks none of that: AC-10 reads
`basename`, which is unchanged, and AC-9 wants a slash-free sibling target, which is still true.

**The GC is the trap.** `ralph-log.sh:95` reaps stale runs with
`find "$LOG_ROOT" -mindepth 2 -maxdepth 2 -type d -mmin +N`. Runs move from depth 2 to depth 3, so
an unchanged GC stops reaping runs and starts reaping **host directories** — deleting a whole
host's evidence in one `rm -rf` on an mtime it never meant to test. The depth is load-bearing and
moves with the layout.

**The readers are the other half.** `loop-doctor.sh:94,100` collect run ids by matching
`[a-z0-9]*-[0-9]*` against a basename found by `find -maxdepth 3`. A pod named `harness-run-7`
matches that glob, so the new host level can be counted as a run. Depth alone is not enough; the
host level has to be excluded by position, not by name.
