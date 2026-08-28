FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=1.17.10

RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"

WORKDIR /home/agent/run-container

ENTRYPOINT ["/usr/bin/tini", "--", "opencode"]
