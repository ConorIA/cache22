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
4. First overlay of `system_files/common/` and `system_files/<variant>/`.
5. `pacman -S` from `packages/<family>-common.txt` and `packages/<variant>.txt`.
6. Second overlay of `system_files/` (re-applies in case package install overwrote anything).
7. Run `scripts/patch-ostree-dracut.sh` to ensure ostree's dracut module is present.
8. Run `scripts/generate-initramfs.sh` to build the initramfs.
9. Run `scripts/finalize-image.sh` for last-mile fixups.
10. Run `bootc container lint` to verify the result is bootable.

The two-overlay pattern (steps 4 and 6) is intentional: package installs may overwrite files from the first overlay; the second overlay restores the cache22 versions.

## packages/

One file per (family, profile) combination:

| File | Applied to |
|---|---|
| `packages/cachy-common.txt` | cachy-kde and cachy-server. |
| `packages/cachy-kde.txt` | cachy-kde only. |
| `packages/cachy-server.txt` | cachy-server only. |
| `packages/arch-common.txt` | arch-kde and arch-server. |
| `packages/arch-kde.txt` | arch-kde only. |
| `packages/arch-server.txt` | arch-server only. |

Format: one package per line. Comment lines start with `#`. Blank lines are allowed.

The build does:

```
pacman -S --needed --noconfirm $(cat packages/<family>-common.txt packages/<variant>.txt | sed 's/#.*//' | grep -v '^[[:space:]]*$')
```

Packages must be available in pacman repositories the build sees. cache22 ships the standard CachyOS or Arch repos plus:

- `cmspam/qemu-patched-v3`. VA-API patched QEMU.
- `cmspam/gamescope-patched`. NVIDIA-fixed gamescope.
- `cmspam/xe-virt-host-v3`. Intel Xe virgl-host packages.
- `cache22-aur` (built in-image at build time). AUR packages cache22 includes.

To add an AUR package:

1. Edit `scripts/build-aur-packages.sh` to include the package name.
2. Add the package to `packages/<...>.txt` so it gets installed from the in-image repo.

## system_files/

Path under `system_files/common/` maps to absolute path in the image:

```
system_files/common/etc/foo.conf      -> /etc/foo.conf
system_files/common/usr/bin/myscript   -> /usr/bin/myscript
system_files/common/usr/lib/systemd/system/myunit.service
                                        -> /usr/lib/systemd/system/myunit.service
```

Per-variant overlays use `system_files/<variant>/` with the same path mapping. Per-variant overlays apply on top of common, so files in both with the same path are overridden by the variant version.

Permissions are preserved as in the source tree. Make scripts executable BEFORE committing:

```
chmod +x system_files/common/usr/bin/myscript
git add --chmod=+x system_files/common/usr/bin/myscript
```

## scripts/

Scripts called by the Containerfile. Edit them to change build behavior.

| Script | Purpose |
|---|---|
| `scripts/rewrite-pacman-paths.sh` | Move pacman state to /usr/lib/sysimage. |
| `scripts/inject-custom-repos-cachy.sh` | Add cmspam/* + cache22-aur to pacman.conf for cachy variants. |
| `scripts/inject-custom-repos-arch.sh` | Same for arch variants. |
| `scripts/build-aur-packages.sh` | Build in-image AUR packages, populate cache22-aur repo. |
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

## See also

- [Forking](../forking/) for the basic fork-and-customize workflow.
- [CI Pipeline](../ci-pipeline/) for what GitHub Actions does with the built image.
