# Red before green — the naming gate proves it can fail

Per `specs/amendments.md` ("Gates must prove they can fail"): `verify.sh` was written first and
run against the tree **before** any rename, then again after. Executor: Claude (orchestrator-
driven, no loop run — a docs rename is not qwen work).

## RED — 2026-08-30, pre-rename tree (branch point = main @ cb59f21)

```
$ STRICT=1 bash specs/20260830a-product-naming/verify.sh
  PASS  scope: every touched file exists
  FAIL  ac1: README title does not open '# Jig' — still unbuilt at the final check (STRICT)
  FAIL  ac1: the README head does not state 'a repo brings a spec and a gate; Jig owns everything else' — still unbuilt at the final check (STRICT)
  FAIL  ac2: board.html is not titled 'Jig Fleet' in both <title> and <h1> — still unbuilt at the final check (STRICT)
  FAIL  ac2: runboard.py is not titled 'Jig Run Board' — still unbuilt at the final check (STRICT)
  FAIL  ac2: coordinator.py fallback page is not titled 'Jig' — still unbuilt at the final check (STRICT)
  PASS  ac3: the ralph-*.sh runtime surface is intact
  PASS  ac3: RALPH_EXEC_CMD binding variable unchanged
  PASS  ac3: harness-coordinator image name unchanged
  PASS  ac3: loop-doctor outcome vocabulary unchanged
  FAIL  ac4: the README's first 'drift' does not carry its definition on the same line — still unbuilt at the final check (STRICT)
  FAIL  ac5: old board titles survive in — scripts/runboard.py scripts/dispatch/board.html — still unbuilt at the final check (STRICT)
  FAIL  ac6: AGENTS.md opening brief does not name Jig — still unbuilt at the final check (STRICT)
exit 1
```

Lenient mode on the same tree exited 0 with every identity check at `pend` — correct
three-verdict staging (unbuilt is pend, STRICT promotes).

Note what stayed green in the red run: **all four AC3 invariance checks.** That is their positive
control direction — they pass on a tree where the bones are intact and fail only on the forbidden
rename. AC5 (an absence assertion) shows its positive control in this very run: the probe fired
on `scripts/runboard.py` and `scripts/dispatch/board.html` before T2 removed the old titles.

## GREEN — 2026-08-30, post-rename tree

```
$ STRICT=1 bash specs/20260830a-product-naming/verify.sh
  PASS  scope: every touched file exists
  PASS  ac1: README title is '# Jig'
  PASS  ac1: the opening states the one-line definition
  PASS  ac2: fleet board titled 'Jig Fleet' (<title> and <h1>)
  PASS  ac2: run board titled 'Jig Run Board'
  PASS  ac2: coordinator fallback page titled 'Jig'
  PASS  ac3: the ralph-*.sh runtime surface is intact
  PASS  ac3: RALPH_EXEC_CMD binding variable unchanged
  PASS  ac3: harness-coordinator image name unchanged
  PASS  ac3: loop-doctor outcome vocabulary unchanged
  PASS  ac4: README defines 'drift' (divergence of copies) where first used
  PASS  ac5: no 'Harness Fleet' / 'Harness Run Board' under scripts/
  PASS  ac6: AGENTS.md opening brief names Jig
exit 0
```

## Neighbouring gates, before vs after

`python3 -m py_compile` clean on both edited Python files. The four spec gates that read the
touched areas were re-run under STRICT on this branch **and** on a clean `main` worktree:

| gate | main | branch |
|---|---|---|
| `20260828f-harness-dispatch` | 0 | 0 |
| `20260828g-dispatch-core` | 0 | 0 |
| `20260828h-dispatch-api` | 1 | 1 — identical FAIL line (`timeout: command not found`, the documented macOS authoring-machine gap) |
| `20260828l-run-control` | 1 | 1 — identical FAIL set, same cause |

The two failures are pre-existing and environmental, not introduced by the rename — exactly the
class #73 (CI runs the repo's own gates) exists to make impossible to miss.
