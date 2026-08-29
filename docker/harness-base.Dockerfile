# harness-base.Dockerfile — the common harness image (no model CLI).
#
# Contains only harness scripts and environment. Third parties can write
# `FROM ghcr.io/mtgibbs/harness-base` and add their own CLI (opencode, codex, claude).
#
# Key contracts:
# - ENV LOOP=/harness/scripts/run-loop.sh
# - ENTRYPOINT ["/usr/bin/tini", "--", "/harness/scripts/run-task.sh"]
# - PATH includes /harness/scripts so run-task.sh and run-loop.sh are reachable by name.
FROM node:22-bookworm-slim

# Install harness prerequisites — same set as the original loop-executor.Dockerfile.
RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Working directory for the harness.
WORKDIR /harness

# Copy only the harness scripts and shared library — no CLI installation.
COPY scripts/ /harness/scripts/
COPY specs/lib/ /harness/specs/lib/

# The harness scripts directory must be on PATH.
ENV PATH="/harness/scripts:$PATH"

# The LOOP environment variable points to the loop script.
ENV LOOP=/harness/scripts/run-loop.sh

# Remote entry point: run-task.sh under tini.
ENTRYPOINT ["/usr/bin/tini", "--", "/harness/scripts/run-task.sh"]
