FROM ghcr.io/mtgibbs/harness-base:0.1.2

ARG OPENCODE_VERSION=1.17.10

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"
