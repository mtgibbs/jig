# MUTANT: ac1
# TARGET: docker/harness-base.Dockerfile
# WHY: describes copying scripts/ and specs/lib/ in a comment but issues no COPY, so the image
# WHY: has an ENTRYPOINT pointing at a run-task.sh that is not in it. A gate that greps the file
# WHY: for the word "scripts" instead of for a COPY instruction reads this as correct.
FROM node:22-bookworm-slim

# The loop lives here: scripts/ and specs/lib/ under /harness.
ENV HARNESS_HOME=/harness
ENV PATH="/harness/scripts:${PATH}"

RUN apt-get update && \
    apt-get install --no-install-recommends -y git ripgrep ca-certificates curl python3 tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /home/agent
ENTRYPOINT ["/usr/bin/tini", "--", "run-task.sh"]
