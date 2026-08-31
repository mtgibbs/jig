# Red before green — and the gate caught its own checker going inert

Per `specs/amendments.md` ("Gates must prove they can fail"): `verify.sh` was written first,
run RED against the pre-work tree, then GREEN after. Executor: Claude (orchestrator-driven,
following the loop methodology by hand — no qwen/opencode loop ran this spec).

## RED — 2026-08-30, pre-work tree (branch point = main @ 23f4bbe)

```
$ STRICT=1 bash specs/20260830f-mutant-observability/verify.sh
  PASS  scope: spec dir holds only its own artifacts
  FAIL  ac1: SELFTEST_EVID emission (no rows from the fixture run) — still unbuilt at the final check (STRICT)
  FAIL  ac2: row schema and marker (no emission yet) — still unbuilt …
  FAIL  ac3: diff capture (no emission yet) — still unbuilt …
  FAIL  ac4: default is write-free, but emission doesn't exist yet so this proves nothing — still unbuilt …
  FAIL  ac5: scripts/mutant-ledger.py — still unbuilt …
  FAIL  ac6: .evidence/selftest-<slug>.jsonl (the real sweep has not been recorded) — still unbuilt …
  FAIL  ac7: committed .evidence/mutant-ledger.{html,md} — still unbuilt …
exit 1
```

## What the gate caught while being written — three findings

1. **The fixture hit the tool's own macOS path-class bug.** A non-git fixture CWD resolves
   LOGICALLY (`/var/…`) while TASK_DIR resolves physically (`/private/var/…`), the prefix strip
   misses, and the tool reports "verify.sh not found" for a gate that is plainly there — the
   exact class the tool's header documents for its `timeout` era. The gate now builds its
   fixture on a physical path and says why.
2. **The link checker went inert on its first green run — Trap A-prime, caught by its own
   control.** The ledger builds per-mutant links CLIENT-SIDE from the embedded JSON payload, so
   a checker grepping static hrefs saw only the 5 template links and the ac7 floor (30) failed.
   The checker now walks the payload's paths too (67 links on the real ledger).
3. **The first positive-control construction planted an invisible bogus row.** Appending the
   bogus row under a fresh `run_id` with its own marker made the generator prefer a phantom run
   with zero rows — the plant was never rendered, so the probe could not fire. The control now
   joins the run the generator actually renders. A positive control that cannot fire is the
   same defect it exists to catch, one level up.

## GREEN — 2026-08-30, post-work

```
$ STRICT=1 bash specs/20260830f-mutant-observability/verify.sh
  … 18 PASS, 0 FAIL   (fixture proves KILLED / SURVIVOR / WRONG-REASON told apart;
                       ledger regenerates byte-for-byte; 67/67 repo links resolve)
exit 0
```

## The recorded sweep (T4)

All six corpora with `SELFTEST_EVID=$PWD/.evidence`: **31 mutants, 31 KILLED** — matching the
unrecorded 2026-08-30 baseline in issue #84. Store: `.evidence/selftest-20260829a-executor-image-layer.jsonl`,
`.evidence/selftest-20260829c-hermetic-gate.jsonl`; render: `.evidence/mutant-ledger.{md,html}`.

## Tool-contract regression check

`specs/20260828k-gate-selftest/verify.sh` after the emission seam landed:

- **end-1 (a bare selftest run leaves the tree byte-identical): PASS** — the invariant this
  change is most able to break, and the reason `SELFTEST_EVID` unset writes nothing.
- end-2/3/4 FAIL — **pre-existing on clean `main @ 23f4bbe`**, verified in a fresh worktree
  before and after this change with identical output: they reference a `20260828g-dispatch-core`
  per-task migration (`tasks/T0*/` with mutant corpora) that is absent from main entirely.
  Same failure class #73 (CI runs own gates) exists to surface; not touched here.
