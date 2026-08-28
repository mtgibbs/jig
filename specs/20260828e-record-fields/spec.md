# Spec: the attempt record says what happened and how long it took

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, jq
- **MCP:** none
- **Touches:** `scripts/ralph-build.sh` (the `log_meta` call sites and the variables they read),
  and the value assertions in `specs/20260826a-evidence-replayable/verify.sh` (§5). **No change**
  to `ralph-log.sh`, `ralph-status.sh`, `run-loop.sh`, or any other spec.

---

## 1. Why · [R — Requirements]

`harness#15`. `specs/20260826a-evidence-replayable` §3.2 specifies seventeen fields on the
per-attempt record. **Three are empty on every record ever written.** Observed on a live run:

```json
{"run_id":"qwen-660081","host":"e061d942c900","attempt":1,
 "outcome":"","duration_s":null,"bytes_prompt":19028,"bytes_patch":1446}
```

`log_meta` reads them from the caller's shell scope, correctly:

```sh
--argjson started "${LOG_STARTED:-0}" --argjson ended "${LOG_ENDED:-0}" \
--arg     outcome "${LOG_OUTCOME:-}"
```

`ralph-build.sh` never sets any of them — `grep -c 'LOG_OUTCOME\|LOG_STARTED\|LOG_ENDED'` returns
**0**. The writer is right; the call sites are incomplete.

**And one of the four outcomes is unreachable.** §3.2 names `passed | failed | noop | stillborn`.
The no-op branch (`ralph-build.sh:182`, "attempt changed nothing") calls `hb_write` and `continue`s
without calling `log_meta` at all — so a no-op attempt leaves **no record whatsoever**, and `noop`
can never appear. No-op attempts are not rare; several occurred during 2026-08-27/28.

**Why it blocks the fleet.** `docs/adr/001-harness-dispatch.md` D6 maps a run's outcome to a coarse
status, and its central rule is that **an unknown outcome reads as `failed`**. Today every record
carries `outcome: ""`. A dispatcher built on D6 would classify every run in the fleet as failed,
correctly, because the field it reads is empty. This is precondition 2 of that ADR.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. Every attempt record carries `outcome` set to exactly one of `passed`, `failed`, `noop`,
   `stillborn` — never the empty string.
2. A **no-op** attempt produces a record at all, with `outcome: "noop"`.
3. `started` and `ended` are unix seconds; `ended` is not before `started`.
4. `duration_s` is a non-negative integer on any attempt that ran.
5. `null` keeps meaning "not measurable" and is not replaced by `0` anywhere it is currently
   correct (§3.2's null-vs-0 discipline).
6. Nothing here can fail a loop — every writer stays best-effort.

## 3. Entities · [E — Entities]

### 3.1 The five points where an attempt ends

| `ralph-build.sh` | situation | `outcome` |
|---|---|---|
| ~166 | executor did not start (nonzero rc, <512B of output) | `stillborn` |
| ~182 | attempt changed nothing — **has no `log_meta` today** | `noop` |
| ~200 | gate green | `passed` |
| ~269 | all attempts exhausted, gate never green | `failed` |
| ~283 | final STRICT gate found unbuilt work | `failed` |

### 3.2 The timing pair

`LOG_STARTED` is stamped once per attempt, at the top of the attempt loop beside the existing
`HB_ATTEMPT="$attempt"`. `LOG_ENDED` is stamped immediately before each `log_meta` call, so it
measures the attempt rather than the loop. `log_meta` already derives `duration_s` from the pair
and already emits `null` when `LOG_ENDED` is unset — that logic is correct and is not changed.

## 4. Approach · [A — Approach]

Set three variables at points that already exist. No new function, no change to `ralph-log.sh` —
the writer has been right the whole time.

**Rejected: passing outcome as an argument to `log_meta`.** Its signature is two positional
parameters and the gate for `evidence-replayable` probes it as `log_meta T1 1`; widening it would
break that gate and re-introduce the nine-parameter mistake that spec's T4 already made once.

## 5. Why this touches another spec's gate · [S — Scope]

`specs/20260826a-evidence-replayable/verify.sh` AC-7 asserts the seventeen keys are **present**:

```sh
jq -e "has(\"$k\")" "$f" >/dev/null 2>&1 || miss="$miss $k"
```

`has("outcome")` is **true for `""`**. That is exactly how three empty fields shipped behind a
green gate, and it is the same shape as `loop-index.py` shipping unwritten behind
`fleet-run-key`'s gate: the assertion was right about what it checked and silent about the
adjacent thing.

Fixing the writer without fixing the detector means the next empty field ships the same way. So
that gate gains **value** assertions alongside its presence ones — `outcome` in the declared set,
`duration_s` a non-negative integer — while keeping every existing check.
