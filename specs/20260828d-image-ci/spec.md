# Spec: the images this repo defines are actually published

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, python3
- **MCP:** none
- **Permissions:** write:.github/**, write:docker/**, write:docs/**, exec:git
- **Touches:** `.github/workflows/build-images.yml` (new — this repo has no `.github/` at all),
  `docker/loop-executor.VERSION` (new), `docs/loop-container.md` (the manual runbook becomes the
  fallback). **No change** to `docker/loop-executor.Dockerfile`, to any script, or to any other
  spec.

---

## 1. Why · [R — Requirements]

`docs/adr/001-harness-dispatch.md` names this **precondition 0**: nothing builds either image the
fleet needs, and the fleet cannot pull what nobody publishes.

`20260828a-exec-container` shipped `docker/loop-executor.Dockerfile` and a manual
`docker buildx … --push` runbook in `docs/loop-container.md`. That is right for a one-off
verification and wrong for a k8s Job that pulls the image on every run: a manual build is a step
someone forgets, and there is no record of which commit produced the running image.

**This repo has no `.github/` directory at all.** The precedent lives in `pi-cluster`
(`.github/workflows/build-review-hub.yml`) because review-hub's code lives there. The rule from
ADR-001 D10 is that the repo owning the code owns its build, so the workflow belongs here — and
this is the first one.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A push to `main` that touches the image's inputs builds and pushes it to GHCR.
2. The image is built for **both** `linux/amd64` and `linux/arm64`, because the workers are Pis.
3. The tag comes from a **version file**, so Flux `ImagePolicy` has a stable pattern to match and
   a bump is a deliberate act rather than a mutable `:latest`.
4. Adding a second image later is **one entry**, not a second workflow.
5. A push that touches nothing relevant does **not** rebuild.
6. `docs/loop-container.md` presents CI as the normal path and the manual `buildx` as the local
   fallback it now is.

## 3. Entities · [E — Entities]

### 3.1 The workflow

`.github/workflows/build-images.yml` — named for the plural deliberately (outcome 4). Modelled on
`pi-cluster/.github/workflows/build-review-hub.yml`, which is a known-good instance of this exact
job in this exact environment:

| element | value | why |
|---|---|---|
| trigger | `push` to `main`, `paths`-filtered | outcome 5 |
| `permissions` | `contents: read`, `packages: write` | least privilege; `GITHUB_TOKEN` is enough for GHCR |
| build engine | `docker/setup-qemu-action` + `setup-buildx-action` | qemu is what makes arm64 buildable on an amd64 runner |
| auth | `docker/login-action` against `ghcr.io` with `secrets.GITHUB_TOKEN` | no PAT to store or rotate |
| platforms | `linux/amd64,linux/arm64` | outcome 2 |
| tag | `ghcr.io/mtgibbs/<image>:<version-file contents>` | outcome 3 |

### 3.2 The image set

A **matrix** over one entry today:

| image | Dockerfile | version file |
|---|---|---|
| `loop-executor` | `docker/loop-executor.Dockerfile` | `docker/loop-executor.VERSION` |

`harness-dispatch` joins as a second row when it exists. That is the whole of outcome 4.

### 3.3 The version file

`docker/loop-executor.VERSION` contains one line, a bare semver (`0.1.0`), no `v` prefix — matching
review-hub's `scripts/reviewhub/VERSION` convention so a Flux `ImagePolicy` written against one
reads the other.

## 4. Approach · [A — Approach]

Copy the shape of the known-good workflow rather than inventing one, and change exactly two things:
a matrix so the image set is data, and a version file per image rather than one for the repo.

**Rejected: `:latest`.** A mutable tag gives Flux nothing to compare and gives an incident no way to
say which commit is running. ADR-001 D6 turns on being able to classify a run; an unidentifiable
image undermines that at the root.

**Rejected: building on tag push.** The repo has no tagging habit, and inventing one to serve CI
means the build is skipped whenever someone forgets. Path-filtered pushes to `main` match how work
actually lands here.

**Rejected: one workflow per image.** Two files that must stay in step is the drift this repo keeps
finding elsewhere — a matrix has one place to change.

## 5. What this spec cannot verify · [A — Approach]

**A gate here cannot prove the workflow runs.** That requires GitHub Actions to execute it, which
happens only after merge. The gate proves the workflow is *well-formed and correct in its
references* — valid YAML, both platforms, real Dockerfile paths, a non-empty version file, the
right permissions — which is every failure mode reachable without a runner.

Two things stay manual and are stated rather than implied:

1. **The first push must be watched.** A workflow that has never run is not known to work.
2. **The GHCR package must be flipped public after the first push**, or the cluster cannot pull it
   anonymously:
   `gh api -X PATCH /user/packages/container/loop-executor -f visibility=public`
   The same footnote appears in the review-hub workflow, which is evidence it is a step people
   forget.
