# MUTANT: ac3
# TARGET: docker/loop-executor.Dockerfile
# WHY: is FROM harness-base — so a grep for the FROM line is satisfied — but re-installs the apt
# WHY: set and re-COPYs the harness on top of it. Two copies of the loop in one image, and the
# WHY: next executor image will copy this file and make a third.
FROM ghcr.io/mtgibbs/harness-base:0.1.0

ARG OPENCODE_VERSION=1.17.10

RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"

COPY scripts/ /harness/scripts/
