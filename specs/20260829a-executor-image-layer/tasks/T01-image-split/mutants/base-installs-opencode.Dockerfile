# MUTANT: ac2
# TARGET: docker/harness-base.Dockerfile
# WHY: bakes opencode into the BASE "so the common case is one image". That is the fork: every
# WHY: derived image now ships a CLI it may not use, and a Claude image inherits a competitor's
# WHY: runtime. The base having no CLI is the entire extension point.
FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=1.17.10

ENV HARNESS_HOME=/harness
ENV PATH="/harness/scripts:${PATH}"

RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl python3 tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"

COPY scripts/ /harness/scripts/
COPY specs/lib/ /harness/specs/lib/

WORKDIR /home/agent
ENTRYPOINT ["/usr/bin/tini", "--", "run-task.sh"]
