# MUTANT: ac4
# TARGET: docs/executors.md
# WHY: is a complete and accurate guide that simply stops before saying what it does NOT do. A
# WHY: reader finishes it believing the image is a working fleet worker, and discovers otherwise
# WHY: inside a pod that ttlSecondsAfterFinished is already deleting.

# Bringing your own executor

| layer | artifact | varies |
|---|---|---|
| the loop | run-task.sh, run-loop.sh | never |
| the strategy | a .conf declaring STRATEGY_PHASES | per run |
| the binding | exec-<tool>.sh plus its CLI | per image |

```dockerfile
FROM ghcr.io/mtgibbs/harness-base:0.1.0
RUN npm install -g @anthropic-ai/claude-code
COPY exec-claude.sh /harness/scripts/
COPY build-claude.conf /harness/scripts/loops/
```

The harness ships no credentials. Auth belongs to your derived image and to the operator.

exec-container.sh is a binding that runs the loop on the HOST and sends each prompt into a
fresh container. Inside a Kubernetes Job the loop is already in the pod, so it uses a direct
binding over the network instead — do not reach for exec-container.sh there.
