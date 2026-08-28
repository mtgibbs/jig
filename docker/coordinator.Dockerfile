# harness-coordinator — the receiving half of the worker channel.
#
# Stdlib only, so there is nothing to install and nothing to keep patched beyond the base image.
# That is deliberate: this service is the thing a human opens when the fleet is misbehaving, and a
# dependency tree is one more way for it to be down at exactly that moment.
FROM python:3.12-slim

RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin coordinator

WORKDIR /app
COPY scripts/dispatch/coordinator.py /app/coordinator.py
COPY scripts/dispatch/board.html    /app/board.html

# State lives on a mount, not in the image layer.
RUN mkdir -p /var/lib/coordinator && chown coordinator:coordinator /var/lib/coordinator
VOLUME ["/var/lib/coordinator"]

USER 10001
EXPOSE 8877
ENV COORD_PORT=8877 \
    COORD_STATE_PATH=/var/lib/coordinator/state.json \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["python3", "/app/coordinator.py"]
