---
title: Variant Switching
parent: System Ops
nav_order: 1
---

# Variant Switching

`cache22-rebase` switches between cache22 variants (cachy ↔ arch, server ↔ kde) or pins to a specific image reference.

## Synopsis

```
sudo cache22-rebase                          # Interactive picker.
sudo cache22-rebase --variant <id>           # Switch by variant id.
sudo cache22-rebase --image <oci-ref>        # Use any OCI reference.
sudo cache22-rebase --reboot                 # Reboot when done.
```

## Variant ids

| Id | Image |
|---|---|
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` |
| `cachy-gnome` | `ghcr.io/cmspam/cache22-cachy-gnome:rolling` |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` |
| `arch-gnome` | `ghcr.io/cmspam/cache22-arch-gnome:rolling` |

## Examples

### Switch from KDE to server

```
sudo cache22-rebase --variant cachy-server --reboot
```

The KDE deploy stays available as a rollback target until the next upgrade after this one. To return to KDE:

```
sudo cache22-rebase --variant cachy-kde --reboot
```

### Pin to a specific build

```
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:2026-05-04
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:sha-9065ce1
```

After pinning, `cache22-update` follows the pinned reference. To return to the rolling stream:

```
sudo cache22-rebase --variant cachy-kde
```

### Interactive picker

```
sudo cache22-rebase
```

Lists available variants from a live catalog (`variants.json` in this repo) plus an option to enter a custom image reference. The catalog is fetched live so new variants show up without an OS update; falls back to the catalog baked into the running image (`/etc/cache22/variants.json`) when offline.

### Switch and reboot in one command

```
sudo cache22-rebase --variant arch-kde --reboot
```

After staging the new variant, the helper exec's `cache22-reboot` with auto-pick. Soft-reboot is unlikely to apply across variants since the kernel and initramfs differ; expect a full reboot or kexec.

## What happens during rebase

Internally, `cache22-rebase` is a wrapper around `bootc switch`. It:

1. Validates the target image reference (must be reachable on the registry).
2. Calls `bootc switch --transport registry <image>`.
3. bootc pulls layers as needed and stages a new deploy.
4. The shutdown sequence finalizes the staged deploy and builds the per-deploy UKI (same path as `cache22-update`).

The previous deploy is preserved as a rollback target until the next upgrade. To return to the previous variant before that next upgrade:

```
sudo bootc rollback
sudo cache22-reboot
```

## Cross-fork rebase

To switch to a fork's image:

```
sudo cache22-rebase --image ghcr.io/<your-username>/cache22-<variant>:rolling
```

The fork's image must follow cache22's UKI structure and per-machine signing model. Switching to a non-cache22 bootc image (e.g., `ghcr.io/ublue-os/bazzite:latest`) is not supported because the new image will not have `cache22-resign-uki` and will not expect sd-boot + per-machine UKI on the ESP.

For cross-bootc moves, use `cache22-repair` from the cache22 live ISO instead. See [Repair](../repair/).

## See also

- [`cache22-update`](../../updates-and-reboots/cache22-update/) for the within-variant update flow.
- [Pinning and Rollback](../../updates-and-reboots/pinning-and-rollback/) for tag mechanics.
- [Variants](../../getting-started/variants/) for what each variant ships.
