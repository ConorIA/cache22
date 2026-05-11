---
title: CI Pipeline
parent: Building and Forking
nav_order: 3
---

# CI Pipeline

The build runs in GitHub Actions, defined by `.github/workflows/build-image.yml`. Each push to the default branch triggers a build for every variant in parallel. A daily scheduled trigger picks up upstream package updates without code changes.

## Triggers

- Push to `main` (or the default branch on a fork).
- Daily schedule at 18:00 UTC.
- Manual workflow_dispatch from the Actions tab.

The build runs on every variant in the matrix unless the changed paths only affect a subset (the workflow does basic path filtering).

## Matrix

```yaml
strategy:
  matrix:
    variant: [cachy-kde, cachy-server, arch-kde, arch-server]
```

All four variants build in parallel. Each variant takes ~22 minutes on GitHub-hosted runners. Total wall-clock time for a full build is ~22 minutes (parallel) plus a few minutes for the manifest aggregation.

## Job steps

Per-variant job:

1. Check out the repository.
2. Install build prerequisites (buildah, skopeo, podman, jq, python).
3. Run `buildah bud` against `Containerfile` with `--build-arg VARIANT=<variant>`.
4. Extract diagnostic artifacts (var-to-tmpfiles output, package manifest).
5. Run `scripts/rechunk-cache22.py` to re-pack into per-package layers.
6. Push to `ghcr.io/<owner>/cache22-<variant>` with three tags:
   - `:rolling`
   - `:YYYY-MM-DD`
   - `:sha-<7chars>`
7. Compute upgrade-size delta vs the previous `:rolling` and post to the GH Actions job summary.
8. Compute package diff vs the previous `:rolling` and post to the job summary.

The diff and delta computation lets the user see exactly what changed in a build without having to pull and inspect the image.

## Determinism

The build is deterministic in a useful sense: the same commit produces byte-identical OCI layers when pacman package versions are the same. Achieved via:

- `libfaketime` wraps signing and dracut at build time so embedded timestamps are constant.
- Sort-order normalization in the rechunker.
- DKMS module-signing disabled (so DKMS module byte content is reproducible across builds).

This is what makes per-layer fetch effective: most daily rebuilds change only a few packages, so only those layers' digests change. Other layers are reused from the local bootc cache.

Determinism is best-effort, not strict. If pacman package timestamps change in upstream, layers re-digest. If a package is rebuilt with new content, its layer changes.

## Artifacts

Each successful build produces:

- The OCI image at `ghcr.io/<owner>/cache22-<variant>:<tag>`.
- A diagnostic artifact attached to the workflow run containing:
  - Full package list (`/usr/lib/sysimage/pacman/local/` listing).
  - var-to-tmpfiles output.
  - bootc container lint output.
  - Layer manifest with sizes.

Diagnostic artifacts are useful for debugging unexpected changes between builds.

## ISO build

A separate workflow (`.github/workflows/build-iso.yml`) builds the live installer ISO. It:

1. Pulls the latest `:rolling` cachy-server image (the ISO is based on cachy-server).
2. Uses `installer/fedora-live/` to wrap a Fedora-based live environment around the cache22 installer scripts.
3. Signs the live kernel with Fedora's MS-signed shim chain (so the ISO boots under stock SB without firmware changes).
4. Publishes to GitHub Releases as `cache22-installer-YYYY.MM.DD.iso`.

The ISO build runs weekly (Sunday) plus on manual dispatch. ISOs are not built per-commit because the live environment changes rarely.

## Failure handling

If a build fails:

- The workflow run shows the failed step and stack trace.
- No new image is pushed for that variant. The previous `:rolling` continues to point at the last successful build.
- Other variants in the matrix may still succeed.

Common failure causes:

- A package was removed from upstream repos. The fix is to remove the package from `packages/<...>.txt` or replace it with a substitute.
- Layer count cap exceeded. The fix is to either consolidate small packages in the rechunker or raise the cap (currently 480).
- Disk space on the runner. GitHub-hosted runners have ~14 GB free; large builds (KDE variants) sometimes hit this. The workflow includes a step to free space at the start.
- Registry push failure. Usually transient. Re-run the workflow.

## Secrets

The build does NOT require secrets to be configured in the repo. GitHub provides `GITHUB_TOKEN` automatically with write access to the same repo's container registry namespace.

What is NOT in the repo:

- SB signing keys (per-machine, generated at install time).
- TPM PCR-policy keys (same).
- Image signing keys for cosign / sigstore (cache22 does not currently sign OCI images).

## Self-hosted runners

The default workflow uses GitHub-hosted runners. To use self-hosted runners:

```yaml
runs-on: [self-hosted, linux, x64]
```

Self-hosted runners can save build time (no cold-start, persistent layer cache via overlay storage) and avoid GitHub-hosted runner disk-space limits. Set up per [GitHub's docs](https://docs.github.com/en/actions/hosting-your-own-runners).

## See also

- [Forking](../forking/) for setting up your own build pipeline.
- [Containerfile and Packages](../containerfile-and-packages/) for what the Containerfile does at each step.
- [Variants](../../getting-started/variants/) for the variant structure the matrix builds.
