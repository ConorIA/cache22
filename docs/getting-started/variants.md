---
title: Variants
parent: Getting Started
nav_order: 3
---

# Variants

cache22 ships four variants. Each is built from one of two base distributions (Arch or CachyOS) and configured for either desktop (KDE) or headless server use.

| Variant | Image | Base + kernel | Use case |
| --- | --- | --- | --- |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` | CachyOS, `linux-cachyos-bore-lto` | Gaming and desktop |
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` | CachyOS, `linux-cachyos-bore-lto` | Headless server |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` | Vanilla Arch + ALHP-rebuilt `linux` | Standard desktop |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` | Vanilla Arch + ALHP-rebuilt `linux` | Headless server |

## Choosing a base

**CachyOS variants** (`cachy-*`) use the [CachyOS](https://cachyos.org/) base distribution. Notable differences from vanilla Arch:

- BORE-LTO scheduler kernel (`linux-cachyos-bore-lto`) optimized for desktop responsiveness.
- v3 packages from CachyOS repos. Many packages rebuilt with x86-64-v3 instructions for performance on modern CPUs.
- Per-kernel pre-built kernel modules for `nvidia-open`, `zfs`, and `r8125`. No DKMS rebuilds at install time.

**Arch variants** (`arch-*`) use the official Arch Linux base. Notable points:

- Mainline `linux` kernel rebuilt by [ALHP](https://alhp.dev/) with x86-64-v3 optimizations.
- DKMS-built kernel modules for `nvidia-open`, `r8125`, `broadcom-wl`, `xone`. These compile against `linux-headers` at image-build time.
- No ZFS support (ZFS is in the cachy variants only via CachyOS's pre-built modules).

## Choosing a profile

**KDE variants** (`*-kde`) include:

- KDE Plasma 6 with SDDM (or `plasmalogin` on cachy variants).
- Steam, Lutris, gamemode, MangoHud, gamescope.
- A SteamOS-style "gamescope mode" toggle: see `cache22-gamescope-mode`.
- Bazaar Flathub storefront for Flatpak.
- Desktop apps: Firefox, Konsole, Dolphin, etc.

**Server variants** (`*-server`) include:

- No display manager, no Wayland or X11 stack, no desktop apps.
- Same container, virtualization, and CLI tooling as KDE variants.
- Smaller install footprint (~6 GB vs ~12 GB for KDE).

## What every variant ships

All four variants include:

- **GPU drivers.** NVIDIA (open driver), AMD, Intel.
- **Filesystems.** ext4, xfs, btrfs, f2fs, NTFS-3G, ZFS (cachy variants only via per-kernel module), exFAT, FAT32.
- **Network.** NetworkManager, OpenVPN, WireGuard, modemmanager, Realtek 2.5G (`r8125` driver).
- **Bluetooth.** bluez stack.
- **Audio.** PipeWire (with PulseAudio, JACK, ALSA shims).
- **Printing.** CUPS with web admin on port 631.
- **Scanning.** SANE.
- **Fingerprint readers.** fprintd.
- **Containers.** podman, docker, distrobox, incus, buildah, skopeo.
- **Virtualization.** QEMU, libvirt, virt-manager (KDE variants), virglrenderer.
- **CLI tooling.** git, openssh, rsync, jq, ripgrep, fd, fzf, btop, tmux, vim, nano, micro, fastfetch, etc.
- **Input methods.** fcitx5 with CJK input modules.
- **Firmware.** linux-firmware, sof-firmware, intel/amd microcode.

The full package list is in `packages/{cachy,arch}-{common,kde,server}.txt` in the cache22 repo.

## Switching between variants

Variants can be switched after install with `cache22-rebase`. The current deployment is preserved as a rollback target. See [Variant Switching](../../system-ops/rebase/).

```
sudo cache22-rebase                         # Interactive picker.
sudo cache22-rebase --variant cachy-server  # By variant id.
sudo cache22-rebase --reboot                # Reboot when done.
```

## Pinning to a specific build

Each successful build pushes three tags per variant:

- `:rolling`. Moves with each build. The default tag for `cache22-update`.
- `:YYYY-MM-DD`. Per-day pointer. The latest build of that day wins if multiple succeeded.
- `:sha-<7chars>`. Immutable per-commit pointer.

To pin to a known-good build:

```
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:2026-05-04
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:sha-9065ce1
```

To return to the rolling stream:

```
sudo cache22-rebase --variant cachy-kde
```

Available tags are listed at `https://github.com/cmspam/cache22/pkgs/container/cache22-<variant>`.
