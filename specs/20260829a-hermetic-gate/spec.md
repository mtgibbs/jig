# hermetic-gate — a gate controls the environment it measures in

Tools: python3 bash git
MCP: none
Permissions: read, write, bash

## Why

A gate is the only voice allowed to say "done". It earns that authority by being deterministic —
the same code must produce the same verdict wherever it runs. Twice now it has not, and both
times the cause was the same: **the gate inherited an environment nobody declared, and the
inherited value changed what the gate measured without changing what it said.**

**Measured 2026-08-29, defect 1 — the workspace.** Every gate begins with `gate_tmpdir`, which
calls `mktemp -d`. In the harness containers `/tmp` is a `noexec` tmpfs, created deliberately by
`tmpfs: /tmp:size=256m` in the compose definition, because docker mounts tmpfs `noexec` by
default. So `mktemp -d` returns a directory nothing can execute from. Running
`T03-push-transcript`'s gate produced exactly one line — `environment: 71a0dd75cbd2` — and exit
2. The same gate with `TMPDIR` pointed at disk passed 4/4. The gate was correct and the code was
correct; only the ambient temp directory differed.

`gate_tmpdir` already builds an exec probe and already detects this. It then gives up. Detection
without recovery means every gate in the repo is one container setting away from being unrunnable,
and the operator must know a variable that appears in no gate's text.

**The same inheritance can go the other way, which is worse.** A `chmod +x` mock on a `noexec`
mount does not fail to exist — it fails with *Permission denied*, non-zero, quickly. An assertion
phrased as "the run exited non-zero" or "finished within 30s" is *satisfied* by that, and passes
green while measuring nothing. The loud failure is the lucky case.

**Measured 2026-08-29, defect 2 — ambient harness configuration.** `T01-push-artifacts` ac1 reads
"with nothing configured the run is line-for-line the run it is today". Its fixture never unsets
`HARNESS_REPORT_URL` or `HARNESS_REPORT_TOKEN`. Those are now set in every harness container, so
the "unconfigured" run inherited the **production coordinator**. Two consequences, both observed
on the live board within seconds of starting a run:

- The assertion never exercised the unconfigured path at all. It compared a configured branch run
  against a configured control run. Pushes are silent by contract, so stdout matched and the
  assertion passed — for a reason nobody chose. Break the unconfigured path tomorrow and this gate
  still passes in any environment that has a URL set, which is now every one of them.
- The fixture loops **posted to production**, landing rows keyed `spec=fx` on the fleet dashboard,
  one carrying ten artifacts. Test data is now indistinguishable from a real run on the board whose
  entire job is to be trusted about what happened, and it shares the eviction path in `harness#46`,
  so fixture rows can push real runs out of a bounded board.

Both defects have one signature: **the check passed, and it passed for a reason that was never
chosen.** That is the failure the ratified amendment *"Name the states a check must tell apart"*
exists to prevent, and it is arriving through the environment rather than through the assertion
text, which is why reading the assertion does not reveal it.

The bar this raises is not "set the variable". It is that a gate must **establish** the conditions
it needs and **neutralise** the ones it does not, in the library, once, rather than in each gate's
text where it will be forgotten exactly when a new container makes it matter.

## What this spec is not

It is not a change to any assertion's meaning. Every gate in the repo must produce the same verdict
after this that it produced before, on a host where it was already correct — this is a change to
the ground gates stand on, not to what they measure.

It does not harden `/tmp`, unharden it, or touch the container definition; `noexec` on a tmpfs is
correct and stays. It does not add a sandbox, a container, or any isolation beyond the environment
of the gate process itself. It does not decide which variables a *fixture* may then opt into — only
that inheriting them silently is not the default.

## The bar

**Fail-closed stays fail-closed.** `gate_tmpdir`'s exit 2 is not a bug; a gate that cannot run must
report neither pass nor fail. Recovery may only widen where a gate looks for a usable workspace. If
no candidate is usable it must still exit 2, still name the environment, and never fall through to
running assertions in a directory it could not validate. A change that turns "cannot run" into
"passes" is the exact defect this spec is about.

**Neutralisation must be visible to the fixture that wants the variable.** A gate that tests the
configured path must still be able to configure it — explicitly, per invocation, the way
`runloop_logged "$T/on" HARNESS_REPORT_URL="$COORD_URL"` already does. The default becomes
"absent"; it does not become "unavailable".

**No gate may reach production.** After this spec, a gate run with the real coordinator configured
in the ambient environment must post nothing to it. This is measurable from outside: the board's
row count must be unchanged across a full gate run.

**The probe must be the arbiter, not the path.** Whether a directory works is decided by writing a
script there, marking it executable and running it — never by matching a name, reading mount flags
or assuming a container. `/home/agent` is right here and means nothing on a laptop or on the arm64
worker, and this library has to keep working in all three.

## Shape

`gate_tmpdir` takes candidates in order — `$TMPDIR`, `$CLAUDE_CODE_TEMP_DIR`, `$HOME/tmp`, `/tmp` —
and for each one that exists and is writable, creates the workspace there and runs the existing
exec probe. First one that passes wins; `T` is set to it and the function returns as it does today.
None pass, and it exits 2 with the environment line it prints today, plus which candidates it tried
and how each failed — a gate that cannot run should say why on the first read, not the third.

Neutralisation belongs beside it, in `specs/lib/assert.sh`, so that sourcing the library is what
establishes the ground. The variables to unset are the harness's own outbound configuration —
`HARNESS_REPORT_URL` and `HARNESS_REPORT_TOKEN` — because those are the ones that reach something
real. Unset them; do not set them to a sentinel, because a sentinel is a URL and something will
eventually try to POST to it.
