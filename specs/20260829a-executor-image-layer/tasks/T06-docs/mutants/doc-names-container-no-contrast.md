# MUTANT: ac3
# TARGET: docs/executors.md
# WHY: mentions exec-container.sh in a list of available bindings but never says how it differs
# WHY: from an in-pod one. Naming both is not contrasting them, and the reader who needs this
# WHY: paragraph is precisely the one who cannot tell them apart.

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

Bindings that ship today: exec-qwen.sh, exec-codex.sh, exec-container.sh.

The harness ships no credentials; auth is your derived image's and the operator's.

This does not provide a Kubernetes Job body, code egress (no push, no pull request), or
credential provisioning.
