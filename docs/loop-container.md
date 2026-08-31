# Loop container — build and run the executor image

**Status:** runbook, 2026-08-28. Owner: Matt.

This document is a runbook, not acceptance criteria in `specs/20260828a-exec-container/verify.sh`, because
the Jig container this spec is built in has **no `docker` available**. A gate that cannot run
here would fail forever, which violates `specs/20260827c-last-task-strict`. Instead, these are real
acceptance criteria that must be proven on a host with `docker`, documented here.

---

## 1. Multi-arch build and push

The `docker/loop-executor.Dockerfile` is written once and must build for both `linux/amd64`
(Beelink) and `linux/arm64` (Pi cluster). Architecture-specific decisions (like the `dpkg`
command in the Dockerfile) are resolved at **build time**, not runtime.

### Normal path: CI on push to main

The image is built and pushed automatically by `.github/workflows/build-images.yml` on every push
to `main` that touches the Dockerfile or `docker/loop-executor.VERSION`.

- The tag comes from `docker/loop-executor.VERSION`, so Flux `ImagePolicy` has a stable pattern to
  match and a bump is a deliberate act rather than a mutable `:latest`.
- The workflow builds for both `linux/amd64` and `linux/arm64` and pushes to `ghcr.io/mtgibbs/loop-executor`.

**To cut a release**, bump the semver in `docker/loop-executor.VERSION` and push.

### Fallback: manual local build

Use this to verify the image builds correctly before merging a change to the Dockerfile or the
version file. It is the only way to validate the image on a host with Docker before merging.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t ghcr.io/mtgibbs/loop-executor:latest \
  -f docker/loop-executor.Dockerfile \
  .
```

### Why `--platform` is passed to buildx, not written into the Dockerfile

- `ARG` and `FROM` in a Dockerfile are evaluated **once per build**. If the Dockerfile hardcodes
  `FROM node:22-bookworm-slim` without `--platform`, Docker chooses the host's architecture.
- A Dockerfile that works for `linux/amd64` cannot produce an `linux/arm64` image in the same
  run — and vice versa.
- Multi-arch is a **build-time property**. Passing `--platform linux/amd64,linux/arm64` tells
  buildx to:
  1. Build both variants in parallel
  2. Create a manifest list pointing to both architecture-specific images
  3. Push the manifest list as `ghcr.io/mtgibbs/loop-executor:latest`
- This is the only way to ensure a single tag (`:latest`) resolves to the correct architecture
  on any client, and it matches the pattern used for official images like `node:`.

### Prerequisites

- A host with `docker` and `docker buildx` installed (not the Jig container).
- Write access to `ghcr.io/mtgibbs/loop-executor` (GitHub Container Registry).
- Network access to push the image.

---

## 2. Acceptance runbook

**Owner:** Matt

**Goal:** Prove item 2 of `docs/design/fleet-dispatch.md` — the binding contract is unchanged:
one spec run via `exec-qwen.sh` and one via `exec-container.sh`, with `.evidence/` differing
**only** in the `binding` field.

### 2.1 Environment the container needs

Per `specs/20260828a-exec-container/spec.md` §3.2, the container requires these environment variables
to be set on the host before invoking `exec-container.sh`:

- `HARNESS_LITELLM_KEY` — LiteLLM API key (required; without it the container cannot reach the
  model and will fail with an authentication or connection error).
- `OC_SHEET` — Google Sheets ID (if the spec uses the sheet feature).
- Any `RALPH_*` variables the loop exports (for logging/metrics).

A variable that is unset in the loop **must remain unset** in the container — never replaced
with the empty string.

### 2.2 Steps

1. **Prepare the environment** on a host with `docker`:

   ```bash
   export HARNESS_LITELLM_KEY=<your-key>
   export ROOT=/home/agent/run-container
   ```

2. **Run one spec via `exec-qwen.sh`:**

   ```bash
   ./scripts/exec-qwen.sh "echo test prompt" | tee /tmp/qwen-run.log
   ```

   Check `.evidence/` for the run key and note the `binding` field (should be `qwen`).

3. **Run the same spec via `exec-container.sh`:**

   ```bash
   ./scripts/exec-container.sh "echo test prompt" | tee /tmp/container-run.log
   ```

   Check `.evidence/` for the run key and note the `binding` field (should be `container`).

4. **Verify the only difference** in the two runs' evidence is the `binding` field:

   - Run keys should be distinct (different timestamps/pids).
   - All other fields (`agent`, `strategy`, `spec`, `outcome`, etc.) must match.
   - The `binding` field differs (`qwen` vs `container`).

### 2.3 Expected failure when `HARNESS_LITELLM_KEY` is absent

If `HARNESS_LITELLM_KEY` is not set in the host environment:

- The container starts successfully (Docker runs the image).
- The executor (`opencode`) exits with an error contacting LiteLLM.
- The log shows an authentication or connection failure to the LiteLLM endpoint.

This is **expected behavior** — the container is correctly passing the environment through.
Fix by exporting `HARNESS_LITELLM_KEY` before running.

---

## 3. References

- `specs/20260828a-exec-container/spec.md` — contract and acceptance criteria.
- `docs/design/fleet-dispatch.md` — fleet design, item 2.
- `docker/loop-executor.Dockerfile` — image definition.
- `scripts/exec-container.sh` — binding script.
