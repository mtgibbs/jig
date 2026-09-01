# MUTANT: ac2
# TARGET: docker/dispatcher.Dockerfile
# WHY: the pin and checksums move but the matched-server record is never written —
# WHY: the next bump re-derives the server version from scratch, which is exactly
# WHY: the re-derivation this task exists to end.
# dispatcher.Dockerfile — the half of fleet dispatch that creates compute.
#
# Follows coordinator.Dockerfile, NOT harness-base. The dispatcher runs no loop and no model: it
# renders a dict and shells out once. Deriving it from harness-base would hand the single component
# permitted to create Kubernetes Jobs an image full of a loop, a node runtime and every harness
# script — the opposite of the blast-radius argument the three-identity table in docs/executors.md
# rests on.
#
# It ships NO credential. api.py refuses to serve without HARNESS_API_TOKEN, and no ENV line here
# may supply one: a default would turn that refusal into a dispatcher accepting unauthenticated
# requests to create compute.
FROM python:3.12-slim

# kubectl, pinned and checksum-verified.
#
# `curl | install` in the one component whose job is to create Kubernetes objects is the
# supply-chain shape this repo refuses everywhere else, and it passes a smoke test on the day you
# write it. The checksums are upstream's own, from
# https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/<arch>/kubectl.sha256
#
# VERSION SKEW: kubectl is supported within one minor of the API server. Check the k3s server
# version before bumping this, and bump it when the cluster moves — a kubectl far ahead of the
# server fails at `apply` time, inside a Deployment, with a message about the resource rather than
# about the skew.
ARG KUBECTL_VERSION=v1.34.11
ARG TARGETARCH
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) KUBECTL_SHA=8efbb9435132a190920eb65a47a8c1ecf755ad85ab57a600c9bedbab460bb7a8 ;; \
      arm64) KUBECTL_SHA=5b045a4712674c88a56fd98eef4285689738b7fbe8735e1b9ee3509521af5cb4 ;; \
      *) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install --no-install-recommends -y curl ca-certificates; \
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "${KUBECTL_SHA}  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/kubectl; \
    apt-get purge -y curl; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin dispatcher

WORKDIR /app
COPY scripts/dispatch/dispatcher.py /app/dispatcher.py
COPY scripts/dispatch/api.py        /app/api.py

# State lives on a mount, not in the image layer. already_seen()/record_seen() are what stop a
# redelivered webhook from launching a second Job for work already running; a ledger that defaults
# into the image is a ledger a restart forgets, and the symptom is duplicate runs rather than an
# error anyone would look for.
RUN mkdir -p /var/lib/dispatcher && chown dispatcher:dispatcher /var/lib/dispatcher
VOLUME ["/var/lib/dispatcher"]

USER 10001
EXPOSE 8878
ENV DISPATCH_PORT=8878 \
    HARNESS_LEDGER_PATH=/var/lib/dispatcher/ledger.jsonl \
    HARNESS_REGISTRY_PATH=/var/lib/dispatcher/registry.jsonl \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["python3", "/app/api.py"]
