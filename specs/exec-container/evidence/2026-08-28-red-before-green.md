# Red before green — `specs/exec-container`

Validated against `9b06fe7`, four ways: empty tree, a stub per presence guard, a stub of a
**wrong** binding, and a control on the fixture itself.

```
$ bash        specs/exec-container/verify.sh ; echo $?   → 0   (10 pend, 2 PASS, 0 FAIL)
$ STRICT=1 bash specs/exec-container/verify.sh ; echo $? → 1
```

## The gate proves the contract without a runtime

There is no `docker` in the harness container. The gate puts a **mock runtime** first on `PATH`,
runs the binding, and asserts the exact argv produced. Each argument is recorded into its **own
file**, never one line each: the fixture prompt contains a newline on purpose, and a line-based
capture would split it and then "prove" byte-for-byte survival against an already-corrupted
sample.

The fixture prompt starts with `-n`, carries a backslash, and spans two lines — the three things
`echo` mangles, and the same trap `log_prompt` was written for.

## Every guard opened, and the wrong answer fails differently

Four presence guards, four stubs — the rule from `specs/fleet-run-key`, where two unopened guards
failed correct work for three attempts.

| guard | stubbed with | result |
|---|---|---|
| `scripts/exec-container.sh` | the correct binding | all ACs PASS |
| `docker/loop-executor.Dockerfile` | arch-neutral base, no USER | PASS |
| `scripts/loops/build-container.env` | strategy pointing at the binding | PASS |
| `docs/loop-container.md` | buildx + both platforms + acceptance | PASS |

A deliberately **wrong** binding — no `--rm`, no `--user`, prompt passed through `$(echo $1)` —
fails on exactly the properties that matter, and the control fires with it:

```
FAIL  ac2: --rm is absent; an ephemeral worker that leaks containers is not ephemeral
FAIL  ac3: no '--user 1001:1001' — files would land as another uid
FAIL  ac4: the last argument is not the prompt verbatim
FAIL  control: the fixture lost its leading -n before the assertion ran
```

The control failing *alongside* `ac4` is the point: it shows the byte-for-byte assertion was
measuring a real hazard rather than restating a tautology.

## What this gate deliberately does NOT assert

The image building, and a real containerised run. Both need `docker`, which this environment does
not have. They are **not** written as `pend` ACs: a pend no run here can ever clear would fail the
final task forever under `specs/last-task-strict`, and a gate that cannot pass is a broken control
rather than a strict one — the lesson from
`specs/evidence-replayable/evidence/2026-08-27-ac8-control-stale-path.md`.

They are handed to a host with `docker` as a runbook with an owner, in `docs/loop-container.md`:
the `buildx` build for both platforms, and fleet-dispatch's own item-2 sketch — one spec run via
`exec-qwen.sh` and one via `exec-container.sh`, with `.evidence/` differing only in `binding`.

## A fourth defect, and a new failure mode for the stub discipline

`ac7` failed T2 three times on a **correct** Dockerfile. Its architecture check was triggered by
the mere string `curl` — but the Dockerfile *installs curl as an apt package*, which is
architecture-neutral because apt resolves the architecture itself. Nothing was being downloaded.

The stub pass did not catch it, and the reason is worth naming: **the stub was not
representative.** It opened the guard — a Dockerfile existed, so the block ran — but it omitted
`curl`, which this spec's own task text explicitly requires. So the assertion executed against a
sample that could not trigger it.

"One stub per presence guard" (`specs/fleet-run-key`) is necessary and not sufficient. The stub
also has to look like what the task actually asks for. A guard opened with an unrepresentative
stub is an assertion that ran without being exercised, which reads as green and proves nothing.

Fixed to trigger on a **URL in a RUN line**, which is what an architecture literal actually hides
in, and validated three ways rather than two:

| Dockerfile | `ac7` |
|---|---|
| installs `curl` as a package, downloads nothing | **PASS** |
| `curl … gh_2.63.2_linux_amd64.deb` | **FAIL** |
| same, with `linux_$(dpkg --print-architecture).deb` | **PASS** |

A second spec defect found in the same run: T2 told the executor to "mirror
`beelink-ansible/files/coding-harness-qwen/Dockerfile`" — a path in **another repository**, which
the executor cannot read from its worktree. Everything needed from it was already reproduced in
the task text, so the reference was decorative and misleading. It now says so.
