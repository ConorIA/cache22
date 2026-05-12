---
title: Containerfile and Packages
parent: Building and Forking
nav_order: 2
---

# Containerfile and Packages

The cache22 image build is driven by `Containerfile` plus the contents of `packages/`, `system_files/`, and `scripts/`.

## Build flow

The `Containerfile` runs these steps in order for each variant:

1. `FROM` the base image (`cachyos/cachyos-v3` for cachy variants, `archlinux/archlinux` for arch variants).
2. Run `scripts/rewrite-pacman-paths.sh` to relocate pacman state from `/var/lib/pacman` to `/usr/lib/sysimage/pacman`. (Required because bootc does not let `/var` be in the OCI layer.)
3. Run `scripts/inject-custom-repos-{cachy,arch}.sh` to add cmspam/* repos and the in-image cache22-aur repo to pacman.conf.
4. First overlay of `system_files/common/` and the per-layer overlays listed in the variant manifest.
5. `pacman -S` from the package list expanded by `scripts/expand-manifest.sh`.
6. Second overlay of the same files (re-applies in case package install overwrote anything).
7. Run `scripts/patch-ostree-dracut.sh` to ensure ostree's dracut module is present.
8. Run `scripts/generate-initramfs.sh` to build the initramfs.
9. Run `scripts/finalize-image.sh` for last-mile fixups.
10. Run `bootc container lint` to verify the result is bootable.

The two-overlay pattern (steps 4 and 6) is intentional: package installs may overwrite files from the first overlay; the second overlay restores the cache22 versions.

## packages/

Layered. Three top-level pieces:

```
packages/
├── layers/
│   ├── cachy/
│   │   ├── base.txt        kernel + system + non-GPU userland (always)
│   │   ├── server.txt      cockpit
│   │   ├── nvidia.txt      pre-built linux-cachyos-nvidia-open + userland
│   │   ├── desktop.txt     GPU userland, fonts, IMEs, generic apps
│   │   ├── gaming.txt      Steam, gamescope, mangohud, lutris, sunshine
│   │   ├── kde.txt         Plasma 6 + KDE apps
│   │   └── gnome.txt       GNOME Shell + GNOME apps
│   └── arch/               same layer names, arch-specific package picks
└── manifests/
    ├── cachy-server.manifest
    ├── cachy-kde.manifest
    ├── arch-gnome.manifest
    └── ... (20 total)
```

A manifest names the layers a variant pulls, one per line, in install order. Comments (`#`) and blanks are ignored.

```
# packages/manifests/cachy-kde.manifest
base
desktop
gaming
nvidia
kde-gaming
kde
```

The build expands the manifest with `scripts/expand-manifest.sh`:

```
pacman -S --needed --noconfirm $(scripts/expand-manifest.sh \
    --family cachy \
    --manifest packages/manifests/cachy-kde.manifest \
    --layers-dir packages/layers/cachy)
```

Each layer's `.txt` file is one package per line, with `#` comments and blanks. A missing `.txt` is treated as empty — useful for system_files-only layers like `kde-gaming`.

Packages must be available in pacman repositories the build sees. cache22 ships the standard CachyOS or Arch repos plus:

- `cmspam/qemu-patched-v3`. VA-API patched QEMU.
- `cmspam/gamescope-patched`. NVIDIA-fixed gamescope.
- `cmspam/xe-virt-host-v3`. Intel Xe virgl-host packages.
- `cache22-aur` (built in-image at build time). AUR packages cache22 needs.

To add an AUR package: just list it in the appropriate layer's `.txt` file. `scripts/build-aur-packages.sh` auto-detects names that no configured pacman repo provides and builds them (plus transitive AUR deps) into the in-image `cache22-aur` repo.

## system_files/

Same layout as `packages/`. Path under `system_files/common/` maps to absolute path in the image:

```
system_files/common/etc/foo.conf      -> /etc/foo.conf
system_files/common/usr/bin/myscript  -> /usr/bin/myscript
```

Per-layer overlays live under `system_files/layers/<family>/<layer>/`. They apply on top of `common/` in manifest order, so files in a later layer override earlier ones (and `common/`).

Intersection layers — content that should only ship when two layers are both active — are named `<a>-<b>` (e.g. `kde-gaming`) and listed explicitly in the manifests where both apply. The `kde-gaming` directory carries the SteamOS-style gamescope session switcher, which depends on both Plasma's login manager and the Steam runtime.

A layer can have a system_files dir without a `.txt` and vice versa.

Permissions are preserved as in the source tree. Make scripts executable BEFORE committing:

```
chmod +x system_files/layers/cachy/desktop/usr/bin/myscript
git add --chmod=+x system_files/layers/cachy/desktop/usr/bin/myscript
```

## scripts/

Scripts called by the Containerfile. Edit them to change build behavior.

| Script | Purpose |
|---|---|
| `scripts/rewrite-pacman-paths.sh` | Move pacman state to /usr/lib/sysimage. |
| `scripts/inject-custom-repos-cachy.sh` | Add cmspam/* + cache22-aur to pacman.conf for cachy variants. |
| `scripts/inject-custom-repos-arch.sh` | Same for arch variants. |
| `scripts/expand-manifest.sh` | Resolve a manifest into a deduplicated package list. |
| `scripts/apply-system-files.sh` | Apply common + manifest-listed system_files layers to a target root. |
| `scripts/build-aur-packages.sh` | Auto-detect + build in-image AUR packages, populate cache22-aur. |
| `scripts/patch-ostree-dracut.sh` | Ensure ostree's dracut module is in the right place. |
| `scripts/generate-initramfs.sh` | Run dracut to build the initramfs. |
| `scripts/var-to-tmpfiles.sh` | Move build-time /var content to /usr/share/factory/var/ + tmpfiles.d. |
| `scripts/finalize-image.sh` | Symlink setup (/home, /opt, /usr/local), preset application, etc. |
| `scripts/rechunk-cache22.py` | Per-package layer rechunking after the initial OCI build. |

## /var handling

bootc (and ostree) require `/var` to be empty in the OCI layer. Anything that pacman or other build steps write to `/var` would otherwise be overwritten by the per-stateroot `/var` at deploy time.

`scripts/var-to-tmpfiles.sh` walks the build's `/var/` and:

1. Moves all files to `/usr/share/factory/var/`.
2. Generates tmpfiles.d entries that recreate the per-stateroot layout from `/usr/share/factory/var/` on first boot.

This means anything pacman writes to `/var` (cache, machine-id placeholder, default subdirectories) gets persisted via tmpfiles, not as part of the OCI layer.

## Per-package layer rechunking

After the initial `buildah bud` produces a single fat layer, `scripts/rechunk-cache22.py` re-packs the image into per-package layers. This makes daily upgrades small: only layers whose contents actually changed are downloaded.

The rechunker:

1. Walks the pacman database to identify each installed package's files.
2. Creates one layer per package (subject to a layer count cap; small packages are batched).
3. Re-emits the OCI manifest with the new layer structure.

The result has ~120 to 480 layers per variant, which is high but supported by modern overlayfs (kernel 6.7+) and bootc.

## bootc container lint

After all build steps, the Containerfile runs:

```
bootc container lint
```

This verifies:

- `/usr` is read-only-mounted at boot.
- The kernel and initramfs are in the right place.
- ostree's dracut module is present.
- No content in `/var` (var-to-tmpfiles handled this).
- BLS / kargs configurations are well-formed.

If lint fails, the build fails. The error message indicates what's wrong.

## Adding a new variant

1. Drop a `packages/manifests/<id>.manifest` listing the layers it pulls, in order.
2. Add a CI matrix entry in `.github/workflows/build-image.yml` (variant id, family, base image).
3. Add a `variants.json` entry (id, label, description, image ref).
4. If the variant introduces a new layer, add `packages/layers/<family>/<layer>.txt` and (optional) `system_files/layers/<family>/<layer>/`.

## See also

- [Forking](../forking/) for the basic fork-and-customize workflow.
- [CI Pipeline](../ci-pipeline/) for what GitHub Actions does with the built image.
