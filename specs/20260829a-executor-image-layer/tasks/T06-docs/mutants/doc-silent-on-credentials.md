# MUTANT: ac2
# TARGET: docs/executors.md
# WHY: never states who owns auth. Harmless-looking on a private base; actively misleading now
# WHY: that harness-base is public, because the obvious assumption for a "base image" is that
# WHY: the platform provides the key.

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

exec-container.sh runs the loop on the HOST and sends each prompt into a fresh container.
Inside a Kubernetes Job the loop is already in the pod and uses a direct binding.

This does not provide a Kubernetes Job body, code egress (no push, no pull request), or
credential provisioning.
