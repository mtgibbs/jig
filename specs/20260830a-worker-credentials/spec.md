# Spec: a worker gets exactly the credentials its strategy needs

**Status:** draft, 2026-08-30. Owner: Matt.

## 1. Why · [R — Requirements]

`render_job` emits a Job carrying three environment variables — `REPO`, `SPEC`, `STRATEGY` — and
nothing else. A pod built from that body can be scheduled and, once the namespace's default
ServiceAccount carries a pull secret, can even start. It cannot reach a model, cannot clone a
private repo, and cannot report. **The fleet's Job body is one field short of being able to do any
work at all**, and that field is the last thing standing between the dispatcher and an ephemeral
worker.

The obvious fix is the wrong one. A single `HARNESS_WORKER_SECRET` mounted into every worker means
every worker carries every provider's key: a `build-codex` run holds the LiteLLM key it will never
use, and a compromised worker of any family holds the credentials of all of them. The repo has
already made this argument once, in
`clusters/pi-k3s/harness/external-secret.yaml` (pi-cluster), refusing to share the coordinator's
token with the dispatch API's:

> the dispatch API creates compute, and this one receives status. A token that leaks from a
> reporting worker should not also be able to launch Kubernetes Jobs, and every worker in the
> fleet carries this one.

The worker is the **least-trusted component in the system**. It runs a model that writes code into
a working tree and then executes that repository's own `verify.sh`. Its credentials should be the
narrowest in the fleet, not the widest.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A dispatched run receives the credentials for **its strategy** and no others.
2. A dispatcher with nothing configured renders **byte-identically** to what it renders today.
3. A local run — laptop or `docker run` — needs no Kubernetes concept whatsoever.
4. The credential contract is written down as a **set of variable names**, so a new context can
   satisfy it without reading the dispatcher.
5. Cloning and landing are **separate identities**, and neither can launch compute.

## 3. Entities · [E — Entities]

**Three identities, and what each may do.** This table is the spec's thesis.

| identity | held by | may |
|---|---|---|
| dispatch API token | the coordinator | create compute (launch Jobs) |
| clone credential | every worker | read the repo it was handed |
| **outcome PAT** | a worker that lands work | push a branch, open a PR — **never** launch compute |

Separating the last two is the point. Today one PAT does both, which means a worker that only ever
needed to read is holding the credential that can write.

> **Correction, 2026-08-31.** This paragraph originally continued: *"It is also why
> `.github/workflows/*` pushes fail from this container: one identity, one scope, and the scope is
> wrong for half its uses."* The symptom is real — such a push is rejected with `refusing to allow
> a Personal Access Token to create or update workflow ... without 'workflow' scope` — but the
> diagnosis was wrong, and it cost a day's worth of workarounds before anyone checked. There are
> **two** identities in that container, not one: `gh`'s token carries `workflow`, and a separate
> narrower PAT sits in `credential.helper store`, which is the one `git` asks first and therefore
> the one that gets refused. Resetting the chain for a single push
> (`git -c credential.helper= -c credential.helper='!gh auth git-credential' push`) succeeds with
> no scope change anywhere; `mtgibbs/harness#76` landed that way.
>
> The argument above is untouched by this — clone and outcome should be separate identities on
> their own merits. What is retracted is only the supporting anecdote. Left as a correction rather
> than an edit because the wrong version is the more instructive artifact: a plausible
> single-identity story explained the error perfectly, and being explicable is not the same as
> being true.

**The credential contract is a set of NAMES, not a mechanism.** `exec-opencode.sh` acquires
nothing — it takes provider configuration from the environment and execs. So every context
supplies the same names its own way:

| context | how they arrive |
|---|---|
| laptop | already exported; `oc` reads Keychain / 1Password |
| local container | `docker run -e` / `--env-file` |
| k8s Job | `envFrom` a Secret |

Outcome 3 falls out of this: `envFrom` is a Kubernetes concept that is simply **not rendered**
when nothing is configured, so a local stack never encounters it.

## 4. Approach · [A — Approach]

`worker_secret(strategy, default)` — the same shape as `worker_image()`, resolved at the same
point, from the same intent:

```
HARNESS_WORKER_SECRET_<STRATEGY_UPPER_SNAKE>   →   HARNESS_WORKER_SECRET   →   nothing
```

Two lookups and a fallback. When it resolves, the rendered Job carries exactly one new field:

```yaml
envFrom:
  - secretRef:
      name: <resolved>
```

When it resolves to nothing, the field is **absent** — not empty, not null. An `envFrom: []` is a
different object from no `envFrom`, and Outcome 2 is a claim about the rendered dict, not about
intent.

Resolved in `dispatch()`, beside the image, for the reason the image is resolved there: the
strategy naming the Job's `STRATEGY` env, the strategy selecting its image, and the strategy
selecting its secret must be **the same value, read once**. A worker running `build-codex` on the
codex image with the LiteLLM strategy's secret is the failure this spec exists to make impossible,
and all three halves read as correct in isolation.

## 5. Scope · [S — Structure: boundary]

### In scope
- `worker_secret()` in `scripts/dispatch/dispatcher.py`, and the `envFrom` it renders.
- The credential contract, documented in `docs/executors.md`.

### Out of scope
- **The manifests.** Namespace, RBAC, ResourceQuota, ExternalSecrets and the node label are
  pi-cluster's, and get their own spec there. `docs/design/fleet-dispatch.md` already draws this
  line: the service deploys in pi-cluster, its contract lives here.
- **Consuming the outcome PAT.** Nothing pushes yet; code egress is its own spec. This spec names
  the identity and reserves the variable so the egress spec inherits a decision rather than making
  one under deadline.
- **`serviceAccountName`.** A pull secret attached to the namespace's default ServiceAccount
  covers image pulls without the Job body naming anything, and adding a field the deploy side does
  not need is how a body that must stay describable stops being describable.
- Every other field of `render_job` — the env list, the nodeSelector, the bounds, the pod spec.

## 6. Prior decisions / facts the implementer must know · [S]

- `worker_image()` (`20260829a` T5) is the shape to copy, including `re.sub(r"[^A-Za-z0-9]", "_",
  strategy).upper()`. Two maps that resolve per-strategy config differently would be two things to
  reason about, and the second one is always the one somebody forgets.
- `render_job` is asserted on by `20260828f` and `20260829a` T05. Adding a key is safe; reordering
  or renaming one is not.
- The gate must compare **rendered dicts**, not YAML text. A field rendered as `None` serialises
  to something a text grep reads as present.
- `specs/lib/assert.sh` unsets `HARNESS_REPORT_URL`/`_TOKEN` at source time, so a worker holding a
  reporting token does not leak it into the fixture runs inside that worker. That property is
  already paid for; do not re-solve it here.

## 7. Norms · [N — Norms]

- No credential value appears in argv, in a log line, or in a rendered Job. Only **names** of
  secrets.
- Fail open on absence: an unconfigured dispatcher launches the run it launches today.

## 8. Safeguards · [S — Safeguards]

- A strategy whose secret variable is unset must not silently inherit another strategy's secret —
  it falls back to the shared default or to nothing, never to a sibling.
- The resolution must not be reachable from the text path's grammar: a requester cannot name a
  secret, only a strategy.

## 9. Task breakdown · [O — Operations]

Sequential. T2 documents what T1 builds.

1. **T1** — `worker_secret()` and the `envFrom` it renders.
2. **T2** — the credential contract in `docs/executors.md`.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

**T1 — the map and the field**

- **AC-1** When `HARNESS_WORKER_SECRET_<STRATEGY>` is set, the rendered Job shall carry
  `envFrom[0].secretRef.name` equal to that value.
- **AC-2** When only `HARNESS_WORKER_SECRET` is set, every strategy shall resolve to it.
- **AC-3** When neither is set, the rendered Job shall contain **no `envFrom` key at all**.
- **AC-4** A per-strategy variable for strategy A shall not be used for strategy B.
- **AC-5** The strategy naming the Job's `STRATEGY` env, selecting its image, and selecting its
  secret shall be the same requested strategy.
- **AC-6** No other key of the rendered Job shall change relative to today.

**T2 — the contract**

- **AC-7** `docs/executors.md` shall name the variables a worker expects.
- **AC-8** It shall state the three delivery contexts and that a local run needs no Kubernetes
  concept.
- **AC-9** It shall record the three identities and that the outcome PAT cannot launch compute.

## 11. Verification (the harness)

`verify.sh` is the convergence gate; `tasks/*/verify.sh` are the per-task gates. Behavioural
through the module's own API, with `launch` monkeypatched so nothing shells out to `kubectl` — the
Job dict handed to it IS the assertion surface, exactly as `20260829a` T05 does it.

AC-3 needs its own control. "No `envFrom`" is an absence, and an absence assertion passes for free
against a dict that failed to render at all — so the gate asserts the absence **and** that the Job
is otherwise complete, in the same check.

## 12. Open questions

- **OQ1 — does the outcome PAT need `workflow` scope?** It would have to, to land a change under
  `.github/workflows/`. That is a real widening of the most dangerous identity in the table, and
  the alternative — the `gh api --method PUT` path this session used twice — works but is
  invisible in a branch's history. Deferred to the egress spec, deliberately: it is a decision
  about what a worker may land, not about how a worker is configured.
- **OQ2 — one secret per strategy, or per strategy *family*?** `build-converge` and
  `build-then-judge` both drive opencode. Per-strategy is what this spec builds because it is the
  shape `worker_image()` already established; collapsing later is cheaper than splitting later.
