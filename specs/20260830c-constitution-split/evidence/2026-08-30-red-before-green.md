# Red before green — and the gate caught its own spec on the first run

Per `specs/amendments.md` ("Gates must prove they can fail"): `verify.sh` was written first, run
RED against the pre-split tree, then GREEN after. Executor: Claude (orchestrator-driven).

## RED — 2026-08-30, pre-split tree (branch point = main @ bad3545)

```
$ STRICT=1 bash specs/20260830c-constitution-split/verify.sh     (dir then named 20260830b-…)
  PASS  scope: every touched file exists
  PASS  scope: spec dir holds only its own artifacts
  PASS  ac1: positive control — the denylist probe fires on a planted 'Flux'
  FAIL  ac1: the constitution still carries consumer law — 5:> reference is `ARCHITECTURE.md` … 9:- **GitOps via Flux.** …
  FAIL  ac2: Tier-1 docs reference absent files — constitution.md:ARCHITECTURE.md README.md:/CLAUDE.md README.md:ARCHITECTURE.md README.md:CLAUDE.md README.md:docs/research/local-coding-agent-sdd.md README.md:plan.md TEMPLATE.md:/CLAUDE.md TEMPLATE.md:docs/research/local-coding-agent-sdd.md
  PASS  ac2: control — extraction is non-degenerate (28 path refs collected)
  FAIL  ac3: specs/README.md lists no spec directories yet
  PASS  ac4: anchor() tolerates an absent file (accumulates ABSENT, never exits)
  PASS  ac4: a missing harness constitution is fatal (exit 2) before any anchor resolves
  PASS  ac5: the judge anchors the harness constitution (line 60) before the project's (line 62)
  FAIL  ac5: the constitution has no consumer-overlay section
  FAIL  ac6: the ratifying amendment is not yet appended
  FAIL  ac6: amendments version line is not 2.x
  PASS  ac6: all five prior amendments survive in order — append-only held
exit 1
```

The checks that stayed green are the invariants whose failure condition is a *forbidden* change
(the judge's anchor shape, append-only history) plus the two positive controls.

## What the first post-work run caught — two findings, one of them about this spec itself

The first GREEN attempt was not green:

```
  FAIL  ac2: Tier-1 docs reference absent files — constitution.md:spec.md
  FAIL  ac3: present but not indexed — 20260830a-worker-credentials 20260830b-dispatcher-image
```

1. **ac3 caught a slug collision, including this spec's own.** `20260830a-worker-credentials`
   and `20260830b-dispatcher-image` had landed on main between the planning sweep and this
   branch — so `20260830a-product-naming` (merged in #80) already collided, and this spec's
   proposed `20260830b-constitution-split` repeated the mistake. This dir was renamed to
   **`20260830c-constitution-split`** before commit. The merged `20260830a` collision is out of
   this spec's scope and flagged to #74 (the neglect-signal sweep).
2. **ac2's extractor over-matched** bare `spec.md` — the constitution's statement of the
   convention names the *member files of any spec dir*, which are not repo paths. The extraction
   gained an explicit exclusion for `spec.md`/`plan.md`/`tasks.txt`, and the re-anchored check
   was verified in **both directions** (the house rule for re-anchors): it still fires on the
   old tree —

```
old constitution:  would-FAIL ARCHITECTURE.md
old specs/README:  would-FAIL /CLAUDE.md · ARCHITECTURE.md · CLAUDE.md · docs/research/local-coding-agent-sdd.md
```

— and passes on the new one.

## GREEN — 2026-08-30, post-split tree

```
$ STRICT=1 bash specs/20260830c-constitution-split/verify.sh
  PASS  scope: every touched file exists
  PASS  scope: spec dir holds only its own artifacts
  PASS  ac1: positive control — the denylist probe fires on a planted 'Flux'
  PASS  ac1: no consumer-specific token in the constitution
  PASS  ac2: every backticked file path in the three Tier-1 docs resolves
  PASS  ac2: control — extraction is non-degenerate (29 path refs collected)
  PASS  ac3: every specs/2026* directory is indexed (36 of them)
  PASS  ac3: the index lists no absent directory
  PASS  ac4: anchor() tolerates an absent file (accumulates ABSENT, never exits)
  PASS  ac4: a missing harness constitution is fatal (exit 2) before any anchor resolves
  PASS  ac5: the judge anchors the harness constitution (line 60) before the project's (line 62)
  PASS  ac5: the overlay section states the assembly order, the overlay's location, and absent semantics
  PASS  ac6: the ratifying amendment is present with Status: Accepted
  PASS  ac6: amendments version went MAJOR (2.x) — the redefinition is owned, not slipped in
  PASS  ac6: all five prior amendments survive in order — append-only held
exit 0
```
