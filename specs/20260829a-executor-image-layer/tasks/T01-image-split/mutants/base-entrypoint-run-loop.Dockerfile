# MUTANT: ac04
# TARGET: docker/harness-base.Dockerfile
# WHY: sets ENTRYPOINT to run-loop.sh instead of run-task.sh. Plausible — run-loop.sh IS the
# WHY: engine — and wrong: run-loop.sh needs a checked-out repo on a throwaway branch, which is
# WHY: what run-task.sh exists to produce. A Job on this image dies in preflight on `main`.
FROM node:22-bookworm-slim

ENV HARNESS_HOME=/harness
ENV PATH="/harness/scripts:${PATH}"

RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl python3 tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/ /harness/scripts/
COPY specs/lib/ /harness/specs/lib/

WORKDIR /home/agent
ENTRYPOINT ["/usr/bin/tini", "--", "run-loop.sh"]
