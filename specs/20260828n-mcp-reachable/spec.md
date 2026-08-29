# Spec: a declared MCP is reachable, not merely configured

Tools: bash python3 git
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

`specs/20260827a-spec-manifest` gave a spec the right to declare `MCP: homelab` and gave the loop
the duty to refuse to start without it. The check it ships with is this, at `run-loop.sh:60`:

```sh
cfg_name="$(basename "$RALPH_EXEC_CMD" .sh).json"
if [ ! -f "$cfg_name" ]; then misses="$misses $cfg_name"; fi
```

**A file exists.** That is the entire proof. The preflight cannot tell a working MCP server from a
broken one, an expired key from a valid one, or a config naming the right server from one naming a
server that was deleted a month ago. It is a check that passes for a reason unrelated to the thing
it claims — the shape the amendment *"gates must prove they can fail"* exists to catch, sitting
inside the gate that was supposed to end preconditions-discovered-the-hard-way.

### What that costs, measured

On **2026-08-28** the homelab MCP was unusable from a Claude session for about an hour, across
three restarts, and every layer of the diagnosis pointed somewhere false:

1. **The config was wrong in a way file-presence cannot see.** `pi-cluster/.mcp.json` referenced
   `${MCP_HOMELAB_KEY}`; the environment defines `MCP_HOMELAB_API_KEY`. The variable resolved
   empty, so the `X-API-Key` header went out blank. The file existed. Any file-presence preflight
   passes this.
2. **The error named the wrong fault.** An empty key produced a `401`, the client fell back to
   OAuth dynamic client registration, and the operator-visible error became
   `HTTP 404: Cannot POST /register` — an HTML 404 that reads as *"the server is down"*. The
   server was healthy the whole time; a direct `POST /mcp` with the correct key returned `200`.
3. **A stale shadow kept it broken after the fix merged.** A project-scoped entry in
   `~/.claude.json` carried a **rotated literal key** and took precedence over the repo config, so
   the corrected `.mcp.json` changed nothing and each restart reproduced the same 404.

Three distinct faults — wrong variable name, misleading error class, shadowing stale config — and
the preflight standing in front of all of them sees none.

### And the container has nothing at all

`docker/loop-executor.Dockerfile` installs `opencode` and nothing else. `specs/20260828a-exec-container`
§3.2 passes `HARNESS_LITELLM_KEY`, `OC_SHEET` and the `RALPH_*` variables — no MCP endpoint, no MCP
credential, no MCP config. So a spec that declares `MCP: homelab` and is dispatched to a container
**passes the preflight** and then discovers at task 1 that no MCP exists: precisely the
burn-a-task-to-find-a-precondition failure `spec-manifest` was written to end, reintroduced by the
deployment target it was written in anticipation of.

**The preflight must ask the server, not the filesystem.**

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A declared MCP server is **proved to answer** before task 1, by one round trip.
2. Failure is **classified**: `unreachable`, `unauthorized`, `not-an-mcp-endpoint`, `unconfigured`.
   `Cannot POST /register` must never be reported as "the server is down".
3. A loop container can reach `mcp-homelab` — endpoint and credential arrive as environment, and
   the in-cluster path carries no ingress, no TLS and no public DNS.
4. A spec declaring `MCP: none`, or declaring nothing, runs **byte-identically to today**.
5. The probe is **read-only** — `initialize` only, never a tool call — and never prints the key.
6. The probe is validated in both directions: a wrong key must classify `unauthorized`, not
   `unreachable`, or the classification is decoration.

## 3. Entities · [E — Entities]

### 3.1 `scripts/mcp-probe.sh` — the question, asked once

```
mcp-probe.sh <server-name> [config-path]   →  stdout: one line   exit: 0 usable, 1 not
```

It resolves the server's URL and its credential's **variable name** from the executor config, then
performs one MCP `initialize` against it. It prints one classification line and exits.

| exit | class | means |
|---|---|---|
| 0 | `ok` | `initialize` returned a `result` with a `serverInfo` |
| 1 | `unconfigured` | no such server in the config, or its key variable is unset/empty |
| 1 | `unreachable` | DNS failure, connection refused, or the bound elapsed |
| 1 | `unauthorized` | the server answered `401`/`403` |
| 1 | `not-an-mcp-endpoint` | the server answered, but not with MCP — including any HTML body, and specifically a `404` on an OAuth-registration path |

`unconfigured` is separated from `unreachable` deliberately: fault 1 above (an env variable named
differently from the one the config interpolates) is a *local* mistake and must not be reported as a
network problem, which is what sent 2026-08-28 looking at the cluster.

`not-an-mcp-endpoint` exists solely because of fault 2. An HTML body is never an MCP answer, and a
probe that lumps it into "unreachable" recreates the hour that motivated this spec.

**Read-only.** `initialize` is the only method sent. It is the one call that must succeed for any
other to, and it mutates nothing.

**Bounded.** Every call carries a short timeout. A server that accepts a connection and never
answers must cost the preflight seconds, not a run.

**Silent about the credential.** The key's *value* never appears in output, in an error, or in a
process argument. Only the variable's *name* is ever printed.

### 3.2 The preflight, rewritten to ask

`run-loop.sh`'s existing MCP block keeps its structure, its collected-misses idiom and its **exit
3** ("container needs attention, not another retry"). Only the question changes: for each declared
non-`none` server, run the probe; on failure, report the server name **and its class**.

The config-path derivation from `RALPH_EXEC_CMD` (`specs/20260827a-spec-manifest` AC-11) is
unchanged — the binding still decides which config file is read. What changes is that the file's
*contents* are now used rather than its existence.

**Absent stays absent.** No `MCP:` field, or `MCP: none`, and not one byte of behaviour differs —
no probe, no network call, no output. This is the portability bar: `run-loop.sh` has to keep
running on a laptop with no infrastructure.

### 3.3 The container's endpoint and credential

| | value | why |
|---|---|---|
| in-cluster URL | `http://mcp-homelab.mcp-homelab.svc.cluster.local:3000/mcp` | Service `mcp-homelab`, port 3000, namespace `mcp-homelab`. A Job talking to a Service in its own cluster has no reason to leave through the ingress, terminate TLS, and resolve a public name to come back in. |
| laptop URL | `https://mcp.lab.mtgibbs.dev/mcp` | unchanged; the ingress path stays for humans |
| credential | `MCP_HOMELAB_API_KEY` | **one name, everywhere.** Fault 1 was two names for one secret. |
| its source | 1Password `mcp-homelab/api-key` → ExternalSecret `mcp-homelab-secrets` | **reuse before mint** — a Job mounts the Secret that already exists. No new credential is created by this spec. |

`scripts/exec-container.sh` passes `MCP_HOMELAB_API_KEY` through with the same discipline §3.2 of
the exec-container spec already sets: **passed through by name, never re-derived, and unset in the
loop means unset in the container** — never the empty string, because an empty key is exactly what
produced the misleading 404.

## 4. Scope · [S]

**In:** the probe, the preflight rewrite, the container's env passthrough, and the documentation of
both URLs and the variable name.

**Out:**
- `mcp-harness` and the dispatcher's own tools — `specs/20260828j-mcp-harness` and ADR-001 **D9**
  own those, and D9's ruling that loop-infrastructure tools do **not** belong in `mcp-homelab`
  stands. This spec is about a worker *consuming* `mcp-homelab`, which D9 does not touch.
- Enforcing `Permissions:`. Still recorded-only, still labelled so.
- Any change to `mcp-homelab` itself. Its `401`-then-client-falls-back-to-OAuth behaviour is a real
  usability wart, but it is a different repo and a different PR; the probe classifies around it.
- Making the probe a general MCP client. It sends one method.

## 5. Facts the implementer must know · [S]

| fact | where | consequence |
|---|---|---|
| the current check is file-presence | `run-loop.sh:60-76` | it is the thing being replaced, not extended |
| the config path comes from the binding | `20260827a-spec-manifest` AC-11 | do not hardcode `opencode.json` |
| exit 3 is the preflight's verdict | `run-loop.sh:80` | keep it; readers key on it |
| the container gets only 3 env groups today | `20260828a-exec-container` §3.2 | MCP env is a fourth, added the same way |
| bash reads a running script by byte offset | `20260825a-evidence-convention` §6b | **the task editing `run-loop.sh` is LAST**, and a nonzero exit right after it is expected — re-invoke, never resume |
| the key already exists in 1Password | `pi-cluster` `docs/secrets-map.md` | reuse; minting a second one recreates fault 1 |

## 6. Safeguards · [S]

- **The credential never leaves as a value.** Not in output, not in an error, not in `ps`.
- **Read-only probe.** `initialize` only. A probe that called a tool would be a preflight with side
  effects.
- **Fail closed on the precondition.** Unlike the worker channel — which fails *open* because
  reporting is observability — an unprovable MCP is a missing precondition and must stop the run
  before task 1. A run that cannot reach its declared MCP has nothing to gain from starting.
- **Bounded.** No probe may hold a run.
- **No new credential, no new ingress.** The in-cluster URL is deliberately not routable from
  outside the cluster.

## 7. Task breakdown · [O]

| # | task | file |
|---|---|---|
| T1 | the probe | `scripts/mcp-probe.sh` (new) |
| T2 | container env passthrough | `scripts/exec-container.sh`, `docker/loop-executor.Dockerfile` |
| T3 | documentation | `docs/loop-container.md` |
| T4 | the preflight asks | `scripts/run-loop.sh` — **LAST**, see §5 |

## 8. Acceptance criteria (EARS) · [O]

- **AC-1** When a server in the config answers `initialize` with a `serverInfo`, the probe shall
  print `ok` and exit 0.
- **AC-2** When the endpoint refuses the connection or does not resolve, the probe shall classify
  `unreachable` and exit 1 within its bound.
- **AC-3** When the endpoint answers `401` or `403`, the probe shall classify `unauthorized` — and
  not `unreachable`.
- **AC-4** When the endpoint answers with an HTML body or a `404` on a registration path, the probe
  shall classify `not-an-mcp-endpoint` — and not `unreachable`.
- **AC-5** When the named server is absent from the config, or the variable its credential
  interpolates is unset or empty, the probe shall classify `unconfigured` — and shall make no
  network call.
- **AC-6** The probe shall never emit the credential's value on any path, success or failure.
- **AC-7** When a spec declares a non-`none` `MCP:` value whose probe fails, `run-loop.sh` shall
  abort before task 1, exit **3**, and name both the server and its class.
- **AC-8** When a spec declares `MCP: none` or omits the field, `run-loop.sh` shall behave
  byte-identically to `origin/main` — no probe, no network call, no added output.
- **AC-9** `exec-container.sh` shall pass `MCP_HOMELAB_API_KEY` through when it is set in the loop's
  environment, and shall leave it **unset** — not empty — in the container when it is unset in the
  loop.

### Validating in both directions

Per `reference_gate_two_direction_validation`, every class needs a fixture that produces it and a
demonstration that `ok` is still reachable:

- **Red before green** — the `401` fixture must classify `unauthorized` and the HTML-404 fixture
  `not-an-mcp-endpoint`. A probe that returns `unreachable` for all three failures passes a
  one-direction test and is worthless; that undifferentiated answer *is* the 2026-08-28 bug.
- **Green is reachable** — a fixture server that answers `initialize` correctly must classify `ok`,
  or the probe has merely disabled every MCP-declaring spec.

## 9. Verification

`verify.sh` stands up small local HTTP servers — one correct, one 401, one HTML-404, one closed
port — and asserts the classification of each, then asserts AC-8 against `origin/main` by running an
`MCP: none` spec through both and diffing. No cluster and no credential is required to run the gate.
