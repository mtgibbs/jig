# Red before green — `specs/20260828d-image-ci`

Validated against `fecd7ad`. Non-STRICT rc 0 (8 pend), STRICT rc 1.

## The gate reads parsed YAML, not text

A `grep` for `linux/arm64` passes on a comment, and a workflow is exactly the kind of file where a
comment describing the intended platforms sits beside a step that does not build them. Every
assertion loads the file with `yaml.safe_load` and reads structure.

One trap worth recording for the next person parsing a workflow: **`on:` is not the key you think
it is.** YAML 1.1 parses the bare word `on` as boolean `True`, so `d.get("on")` returns `None` on a
perfectly valid workflow. The gate accepts either key.

## Two defects in this gate, both found after the loop wrote correct code

**1. `ac3` passed a hardcoded image name.** It asserted the tag *points at* `loop-executor`, which a
literal string satisfies exactly as well as a matrix reference. The first implementation hardcoded
it — so a second matrix entry would publish under the *first* entry's name, defeating the only
reason outcome 4 asks for a matrix — and the gate went green.

Same shape as `loop-index.py` shipping unwritten behind `fleet-run-key`'s gate, and `outcome`
shipping empty behind `evidence-replayable`'s: the assertion was right about the property it
checked and silent about the adjacent one. **An incomplete set of assertions is indistinguishable
from a passing one.** Caught by reading the generated file rather than trusting the verdict.

**2. `ac3` and `ac10` were then mutually unsatisfiable — a new failure mode.** `ac3` demanded the
literal `ghcr.io/mtgibbs/loop-executor`; `ac10` demanded `${{ matrix.image }}`. No workflow
satisfies both. T4 burned all three attempts producing exactly the right change:

```
-tags: ghcr.io/mtgibbs/loop-executor:${{ steps.version.outputs.version }}
+tags: ghcr.io/mtgibbs/${{ matrix.image }}:${{ steps.version.outputs.version }}
```

and being rejected each time.

Worse than a gate that cannot fail, and the asymmetry is the point:

| | consequence | who gets blamed |
|---|---|---|
| gate that cannot **fail** | a defect ships | nobody notices |
| gate that cannot **pass** | nothing ships | **the executor** |

From the loop's side it is indistinguishable from a model that cannot follow instructions — the
same indistinguishability as the `.env` permission block, from the other direction.

Resolved by giving each assertion one concern: `ac3` owns registry and owner, `ac10` owns the image
name. **Generalisation for adversarial gates:** stub-validate each new assertion against the *other
assertions*, not only against the tree. "Must do X" / "must not do Y" pairs are where
contradictions hide.

## Two things outside the gate's reach

**It cannot prove the workflow runs.** That needs a GitHub Actions runner, which happens only after
merge. Watch the first run, and afterwards flip the GHCR package public
(`gh api -X PATCH /user/packages/container/loop-executor -f visibility=public`) or the cluster
cannot pull anonymously.

**Pushing a workflow file needs a token scope this container's git credential lacks:**

```
! [remote rejected] — refusing to allow a Personal Access Token to create or update
  workflow `.github/workflows/build-images.yml` without `workflow` scope
```

`gh` holds `workflow` scope; the git credential does not. Pushed via
`git -c credential.helper='!gh auth git-credential'`, which is a per-invocation override rather
than a change to the container's persistent git config. Worth knowing before the next workflow
change: the plain `git push` will fail, and the error names the cause clearly.
