# Run control — resume, retry, and polling-based control

**Status:** user guide, 2026-08-28. Owner: Matt.

A Jig loop runs as a containerized worker that **cannot receive external signals**. A loop in a
k8s Job or a standalone container has no published port, and a loop in a Job ceases to exist when
it finishes. So a control cannot be *sent* to a worker; the worker must **notice** it by polling.

## Resume and retry

### Satisfied tasks

A task is *satisfied* if its own gate passed **before** the executor runs. Under a per-task-gate
spec (e.g., `20260828i`), each task has an independent gate, and the loop can ask *is task N
already done?* and skip it.

- A satisfied task is announced and heartbeated; no executor call is made and no attempt is
  consumed.
- A monolithic-gate spec has no per-task gates and cannot answer *is task N done?* — the loop
  behaves exactly as today ( Outcome 3).
- A task whose gate is not green never passes; the loop never lies and never lets a red gate look
  green.

### Resume from a specific task

Set `RALPH_FORCE_FROM=<n>` to skip tasks 1..n-1 and run task n and onward. This is how you retry
from a specific point.

```bash
RALPH_FORCE_FROM=3 scripts/ralph-build.sh specs/20260828l-run-control
```

### Force every task

Set `RALPH_FORCE_ALL=1` to disable skipping entirely. Every task runs, even if its gate is green.

```bash
RALPH_FORCE_ALL=1 scripts/ralph-build.sh specs/20260828l-run-control
```

## Polling-based control

Run control decisions live **between tasks** and **between attempts**. A worker checks for a
control signal (later spec: `HARNESS_CONTROL_URL` or a local file) and decides what to do next.
Nothing can connect *into* the worker; the worker must poll outbound and discover cancellation or
pause instructions while polling.

This matches how production systems actually work: GitHub Actions and GitLab runners both poll
outbound and discover cancellation while polling. Nothing dials the agent.
