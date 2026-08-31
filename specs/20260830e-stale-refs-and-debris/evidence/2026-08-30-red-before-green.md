# Red before green — and the gate out-found its own spec on the dry run

Per `specs/amendments.md` ("Gates must prove they can fail"): `verify.sh` was written first,
run RED against the pre-sweep tree, then GREEN after. Executor: Claude (orchestrator-driven).

The resolver's dry run found **three dangling references issue #74 never enumerated**
(`docs/adr/008-…` and `scripts/exec-qwen.sh` in the README; the relative-path breakage in
ADR-001 and the 2026-08-27 run doc), which is the spec's own §1 thesis measured a third time:
a hand-maintained list is stale the moment anything moves; the gate stays true on its own.

## RED — 2026-08-30, pre-sweep tree (branch point = main @ 30f35a9)

```
$ STRICT=1 bash specs/20260830e-stale-refs-and-debris/verify.sh
  PASS  scope: spec dir holds only its own artifacts
  PASS  ac1: positive control — the resolver flags a planted bogus path
  FAIL  ac1: dangling references — README.md:docs/adr/008-review-hub-framework-seam.md README.md:docs/research/codemap-serena-token-efficiency.md README.md:scripts/exec-qwen.sh docs/adr/001-harness-dispatch.md:ARCHITECTURE.md docs/adr/001-harness-dispatch.md:clusters/pi-k3s/mcp-homelab/clusterrole.yaml docs/adr/001-harness-dispatch.md:fleet-dispatch.md docs/adr/001-harness-dispatch.md:flux-system/infrastructure.yaml docs/runs/2026-08-27-evidence-replayable-first-run.md:evidence/2026-08-26-red-before-green.md
  PASS  ac1: control — extraction collected 31 path refs (threshold 20)
  PASS  ac2: positive control — the .env probe fires on a planted fixture
  FAIL  ac2: a doc still describes strategies as .env — README.md:47 …
  FAIL  ac3: .evidence/README.md (cited by scripts/loop-index.py) — still unbuilt at the final check (STRICT)
  FAIL  ac3: ralph-judge-exec-qwen.sh still cites scripts/README.md, which does not exist
  FAIL  ac3: scripts/ralph-bus.sh cites docs/agent-bus.md without the pi-cluster/ external marker — 15:…
  FAIL  ac3: scripts/agent-bus-bootstrap cites docs/agent-bus.md without the pi-cluster/ external marker — 7:… 42:…
  FAIL  ac4: docs/research/codemap-serena-token-efficiency.md (imported from pi-cluster) — still unbuilt at the final check (STRICT)
  FAIL  ac5: repo-root tasks/ still exists — tasks/T03-missing-mutants/verify.sh tasks/T01-workspace/verify.sh
  FAIL  ac6: LICENSE — still unbuilt at the final check (STRICT)
  FAIL  ac6: CONTRIBUTING.md — still unbuilt at the final check (STRICT)
  PASS  ac7: positive control — the duplicate-prefix probe fires on a planted collision
  FAIL  ac7: spec-slug prefix collision — 20260830a
  FAIL  ac7: specs/20260830d-product-naming (the renamed dir) — still unbuilt at the final check (STRICT)
exit 1
```

12 FAILs; the 5 PASSes are the scope check, the extraction floor, and the three positive
controls — exactly the lines that must be green for the red to mean anything. Note this red
is a **near-miss red, not an empty-tree red** (the 2026-08-27 run doc's lesson): every `no`
fired on a real artifact that existed and was wrong.

## GREEN — 2026-08-30, post-sweep

```
$ STRICT=1 bash specs/20260830e-stale-refs-and-debris/verify.sh
  … 17 PASS, 0 FAIL
exit 0
```

Extraction count moved 31 → 26 across red → green: the five ADR-001 infra paths left the
corpus when they gained the `pi-cluster/` marker, and the imported research doc brought new
in-repo refs. Both counts clear the floor of 20; the delta is the marker working, not the
filter going inert.

## The rename disarmed nothing

`git mv specs/20260830a-product-naming specs/20260830d-product-naming`, then both gates the
move could have silently broken were re-run strict:

```
$ STRICT=1 bash specs/20260830d-product-naming/verify.sh    → exit 0
$ STRICT=1 bash specs/20260830c-constitution-split/verify.sh → exit 0   (index parity, both ways)
```

Live references updated: `specs/README.md` (index entry) and the moved gate's own header
comment. Commit messages and `specs/*/evidence/` transcripts keep the `20260830a-` slug as
history — records are not rewritten.

## Mutant accounting for this run

Vocabulary per `specs/20260828k-gate-selftest`: a **mutant** declares the assertion it must
break; the gate kills it or it survives as the headline failure.

This spec ships a **whole-spec gate with no per-task `mutants/` corpus** — its adversaries are
the three ephemeral inline fixtures (mktemp'd, never committed, per TEMPLATE §11's
keep-the-adversary-out-of-the-repo rule):

| inline mutant | targets | verdict |
|---|---|---|
| planted `docs/this-file-does-not-exist.md` citation | ac1 resolver | killed (control PASS, red + green) |
| planted `scripts/loops/<name>.env` line | ac2 probe | killed (control PASS, red + green) |
| planted `20260830a-one`/`20260830a-two` prefix pair | ac7 dup probe | killed (control PASS, red + green) |

Survivors: none. The pre-sweep tree itself served as a 12-defect natural mutant corpus (table
above — every defect a distinct assertion, every one killed).

Noted for the monitoring/visualization thread (owner request, 2026-08-30, mid-run): mutant
kills/survivors are currently only legible by reading gate transcripts like this one. If the
fleet visualizations are to show gate health, the kill/survive counts per run belong in a
machine-readable store (the `.evidence/` index rows already carry per-run verdicts — the
natural seam), not in prose.
