# evidence-egress — the attempt's artifacts leave the worker as they are produced

## Why

A drill-down into a run is empty today. The loop already writes everything a reader wants —
the prompt the executor was given, the diff it produced, the gate's per-assertion verdicts, the
transcript of what it actually did — and writes all of it into `.evidence/runs/`, which is
gitignored and lives inside a container nothing can connect to. The evidence is complete and
unreachable at the same time.

ADR-001 D5 said evidence must leave the pod and was never built, because it was framed as
*retrieval*: something goes and fetches the artifacts when a run finishes. That framing cannot
work here. Nothing can dial into a worker, and a run that dies — the case where the evidence
matters most — leaves nothing to fetch from. A k8s Job is worse still: the pod name is gone
moments after it exits.

So invert it, the way a CI runner does. The worker **pushes each artifact at the moment it is
written**, over the same outbound channel `20260828m-worker-channel` established for status. An
artifact that has already left cannot be lost by the process that dies afterwards.

## What this spec is not

It is not the coordinator. Nothing here decides how artifacts are stored, indexed, retained or
served — this spec ends at the POST. It is not the dashboard. It does not add polling, controls,
or any inbound path, and it introduces no second identity: artifacts are keyed by the run key the
loop already has, plus the task and attempt the artifact belongs to.

## The bar

**Portability is the requirement, not a preference.** With no coordinator configured the loop
must behave exactly as it does today — write its files, post nothing, print nothing. `run-loop.sh`
has to keep working on a laptop with no infrastructure, and that is the property this whole
design exists to preserve.

**Failure must be total and silent.** An unreachable coordinator, a refused connection, a 500, a
timeout, a body larger than the far end will accept: none of them may fail, stall, or alter the
run, and none may print anything a reader could mistake for a loop error. The evidence channel
reporting on a build must never be able to break the build it reports on.

The cap is `HARNESS_ARTIFACT_MAX_BYTES`, defaulting to a value the implementation chooses; a
truncated artifact announces itself with the word `truncated` and its original byte count.

**Truncation must be visible.** These artifacts are bounded — a diff carrying untracked file
contents runs to tens of kilobytes and a pathological one is unbounded. Whatever bound is chosen,
a truncated artifact must announce itself, because a reader who cannot tell a complete diff from a
clipped one will conclude the executor did less than it did. A silently short artifact is the same
class of defect as a check that cannot fail: the benign reading wins and nobody learns otherwise.

## Shape

    POST {base}/runs/{run_key}/attempts/{task}/{attempt}/artifacts/{kind}

`{task}` is the SHORT label — `T1`, not the task's prose. `ralph-log.sh` already derives it with
`log_task`, which reduces `T1: make a.` to `T1` and yields `Tx` for anything unparseable; the path
segment must reuse that function rather than re-deriving it, so the artifact's URL and the
artifact's filename always name the same task. The full task text is already carried in the status
record and does not belong in a URL.

`kind` is one of `prompt`, `patch`, `diff`, `gate`, `meta`, `log`. Body is the artifact's bytes. The same
`HARNESS_REPORT_URL` / `HARNESS_REPORT_TOKEN` configuration as status, the same bearer header, the
same bound, the same silence.

The call sites already exist and are single: `log_prompt`, `log_gate`, `log_failure`,
`log_patch` and `log_meta` each write exactly one file through `log_path`, and the executor's
transcript is written by the caller.

**`patch` and `diff` are not the same artifact and neither substitutes for the other.**
`log_patch` runs on a PASSING attempt and writes an applyable patch — the change that was
actually kept. `log_failure` runs on a FAILING attempt and writes a diagnostic bundle: the verify
output, the tracked diff, and the contents of untracked files the reset is about to delete. Most
tasks pass, so `patch` is the artifact carrying the file changes a reader will look at most often,
and a design that shipped only `diff` would show file changes exclusively for work that failed. Push from where the file is written, not from a sweep that walks the
directory afterwards — a sweep re-reads files the run may already have cleaned, and cannot
distinguish an artifact from this attempt from one left by the last.
