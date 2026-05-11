---
title: Forking
parent: Building and Forking
nav_order: 1
---

# Forking

To build your own variant of cache22 (different packages, custom config, additional desktop, custom branding), fork the repository and edit the relevant files. The full pipeline runs in your fork's GitHub Actions.

## Prerequisites

- A GitHub account.
- Permission to enable GitHub Actions on your fork (default for public forks).
- A `ghcr.io` namespace under your account (created automatically when the first image is pushed).

## Step 1. Fork on GitHub

Open `https://github.com/cmspam/cache22` and click "Fork". GitHub creates `https://github.com/<your-username>/cache22` and copies the default branch.

GitHub Actions activates automatically on the fork. The first push or schedule trigger will start a build.

## Step 2. Edit configuration to taste

The main customization points:

| Path | Purpose |
|---|---|
| `packages/layers/<family>/<layer>.txt` | Per-layer package lists (one per line). |
| `packages/manifests/<variant>.manifest` | Per-variant list of layers, in install order. |
| `system_files/common/` | Files overlaid on top of the base image for every variant. Path under `system_files/common/` maps to absolute path in the image. |
| `system_files/layers/<family>/<layer>/` | Per-layer overlay applied when that layer is in the variant's manifest. |
| `Containerfile` | Image build recipe. Usually no edits needed. |
| `variants.json` | Variant catalog used by the installer's interactive picker. |

For example, to add `htop-vim` to every variant:

```
echo 'htop-vim' >> packages/layers/cachy/base.txt
echo 'htop-vim' >> packages/layers/arch/base.txt
git commit -am "add htop-vim"
git push
```

The push triggers a build. ~22 minutes per variant, all 20 building in parallel.

## Step 3. Install your fork

Use the cache22 live ISO (the one published by `cmspam/cache22`, since your fork's ISO build follows the same pipeline and your forked ISO won't be ready until your first build completes):

```
cache22-install --image ghcr.io/<your-username>/cache22-<variant>:rolling
```

Or, if you've already done a release of your own ISO from your fork:

Use your fork's ISO from `https://github.com/<your-username>/cache22/releases/latest`.

## Step 4. Update flow on your fork

Once installed, day-to-day updates from your fork follow the same flow:

```
sudo cache22-update
sudo cache22-reboot
```

`cache22-update` follows the image reference baked in at install time. It tracks `:rolling` of your fork by default.

## What does NOT need configuration

- **CI signing keys.** cache22 uses per-machine signing only. There are no signing secrets to set in your GitHub repo. UKI signing happens at install time on each user's machine.
- **Container registry credentials.** GitHub Actions has automatic write access to your `ghcr.io` namespace via the built-in `GITHUB_TOKEN`.
- **Workflow file.** `.github/workflows/build-image.yml` runs as-is.

## Common customizations

### Add a package to all variants

Edit `packages/layers/cachy/base.txt` and `packages/layers/arch/base.txt`:

```
emacs-nox
```

(One per line. No version specifiers; the build uses whatever the upstream repo provides.)

### Add a package to KDE only

Edit `packages/layers/cachy/kde.txt` and `packages/layers/arch/kde.txt`:

```
kdenlive
```

### Add a new variant

Drop a manifest at `packages/manifests/<id>.manifest` listing the layers it pulls, then add a row to the CI matrix in `.github/workflows/build-image.yml` and an entry in `variants.json`. See [Containerfile and Packages](../containerfile-and-packages/#adding-a-new-variant).

### Drop a system file (overlay)

To bake `/etc/foo.conf` into the image:

```
mkdir -p system_files/common/etc
cat > system_files/common/etc/foo.conf <<EOF
key=value
EOF
git add system_files/common/etc/foo.conf
git commit -m "add /etc/foo.conf"
git push
```

The file lands at `/etc/foo.conf` on the running system after the next image build is pulled.

### Add a per-machine systemd unit

To enable a service on first boot:

```
mkdir -p system_files/common/usr/lib/systemd/system
cp my-service.service system_files/common/usr/lib/systemd/system/
echo 'enable my-service.service' >> system_files/common/usr/lib/systemd/system-preset/50-cache22.preset
```

The preset is applied at image-build time via `systemctl preset-all --preset-mode=full` in `scripts/finalize-image.sh`.

### Replace cache22 branding

Edit:

- `system_files/common/usr/lib/os-release`. Set `NAME`, `PRETTY_NAME`, `VARIANT`, `VARIANT_ID`, `BUG_REPORT_URL`.
- `system_files/common/usr/share/factory/etc/issue`. Login banner.
- `variants.json`. The display names shown by the installer's picker.

### Change the kernel

For cachy variants: replace `linux-cachyos-bore-lto` in `packages/layers/cachy/base.txt` with another CachyOS kernel (e.g., `linux-cachyos`).

For arch variants: the kernel is `linux` by default. Replace with `linux-lts`, `linux-zen`, or any other Arch-packaged kernel.

Per-kernel modules (`*-nvidia-open`, `*-zfs`) need to match the chosen kernel. Update those references too.

### Disable a variant entirely

In `.github/workflows/build-image.yml`, remove the matching `include:` rows from the matrix. Each row defines one variant; deleting it skips that build entirely.

Or leave the matrix alone and just delete the matching `packages/manifests/cachy-*.manifest` files. The build for those variants will fail, which is fine if you do not need them.

## What gets pushed

Each successful build pushes three tags per variant to `ghcr.io/<your-username>/cache22-<variant>`:

- `:rolling` (moves with each build).
- `:YYYY-MM-DD` (latest build of that day).
- `:sha-<7chars>` (immutable per-commit).

See [Pinning and Rollback](../../updates-and-reboots/pinning-and-rollback/) for using these tags.

## Branching

For experimental changes, create a branch:

```
git checkout -b experiment
# ... edit ...
git push -u origin experiment
```

The build runs on every branch push. Images for branch builds are tagged `:experiment-rolling`, `:experiment-YYYY-MM-DD`, etc.

To install from a branch:

```
sudo cache22-rebase --image ghcr.io/<your-username>/cache22-cachy-server:experiment-rolling
```

## See also

- [Containerfile and Packages](../containerfile-and-packages/) for what each part of the build does.
- [CI Pipeline](../ci-pipeline/) for the GitHub Actions workflow details.
- [Variants](../../getting-started/variants/) for the existing variant structure.
