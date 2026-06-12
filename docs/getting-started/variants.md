---
title: Variants
parent: Getting Started
nav_order: 3
---

# Variants

cache22 ships six variants. Each pairs one of two base distributions (CachyOS or vanilla Arch) with one of three roles (headless server, KDE Plasma desktop, or GNOME desktop). NVIDIA proprietary driver and gaming stack (where applicable) are built in.

| Variant | Image | Base + kernel | Use case |
| --- | --- | --- | --- |
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` | CachyOS, `linux-cachyos` | Headless server / container host |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` | CachyOS, `linux-cachyos` | KDE Plasma desktop + gaming |
| `cachy-gnome` | `ghcr.io/cmspam/cache22-cachy-gnome:rolling` | CachyOS, `linux-cachyos` | GNOME desktop + gaming |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` | Arch, mainline `linux` | Headless server / container host |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` | Arch, mainline `linux` | KDE Plasma desktop + gaming |
| `arch-gnome` | `ghcr.io/cmspam/cache22-arch-gnome:rolling` | Arch, mainline `linux` | GNOME desktop + gaming |

Earlier revisions of cache22 split out NVIDIA and gaming into separate variants (20 in total). That matrix was retired in favor of these six: keeping it reliable on GHA-hosted CI ran into ghcr.io rate limits and runner concurrency caps. The cost is ~250 MB of unused NVIDIA firmware/driver on AMD-only hardware, and the gaming stack (Steam, gamescope, lutris, sunshine) installed on desktop variants whether you use it or not.

## Choosing a base

**CachyOS variants** (`cachy-*`) use the [CachyOS](https://cachyos.org/) base distribution:

- Default CachyOS kernel (`linux-cachyos`): clang + ThinLTO, AutoFDO-profiled, EEVDF scheduler, 1000 Hz tickrate.
- v3 packages from CachyOS repos. Many rebuilt with x86-64-v3 instructions.
- Per-kernel pre-built modules for `nvidia-open`, `zfs`, and `r8125`. No DKMS rebuilds at image-build time.

**Arch variants** (`arch-*`) use the official Arch Linux base:

- Mainline `linux` kernel.
- DKMS-built modules for `nvidia-open`, `r8125`, `r8152`, `broadcom-wl`, `xone`. Compiled against `linux-headers` at image-build time.
- No ZFS support (ZFS is cachy-only via CachyOS's pre-built module).

## Choosing a role

**`server`.** No display manager, no Wayland or X11 stack, no desktop apps. Containers (podman, docker, distrobox, incus), libvirt+qemu, cockpit web admin. ~6 GB on disk.

**`kde`.** KDE Plasma 6 with `plasma-login-manager`, Dolphin, Konsole, Discover, Bazaar Flathub storefront, Firefox. Plus the gaming stack and SteamOS-style switchable gamescope session via `cache22-gamescope-mode`.

**`gnome`.** GNOME Shell with GDM, Nautilus, Loupe, Papers, Bazaar. Plus the gaming stack. No SteamOS session switcher (that's KDE-only today — driven by `plasma-login-manager` autologin).

## What every variant ships

The base layer (always installed) includes:

- **GPU drivers.** Mesa (AMD, Intel, virtio) + NVIDIA proprietary (`nvidia-open-dkms` on arch, `linux-cachyos-nvidia-open` on cachy).
- **Filesystems.** ext4, xfs, btrfs, f2fs, exFAT, FAT32, NFS, SMB. ZFS on `cachy-*` only.
- **Network.** NetworkManager, OpenVPN, WireGuard, modemmanager, `r8125` (PCIe), `r8152` (USB).
- **Bluetooth.** bluez stack.
- **Audio.** PipeWire (with PulseAudio, JACK, ALSA shims).
- **Containers.** podman, podman-compose, docker, docker-compose, distrobox, incus, lxc.
- **Virtualization.** qemu-base, libvirt, virglrenderer, swtpm, edk2-ovmf.
- **CLI tooling.** git, openssh, rsync, jq, ripgrep, fd, fzf, btop, tmux, vim, nano, micro, fastfetch.
- **Firmware.** linux-firmware, sof-firmware, intel/amd microcode.
- **Desktop add-ons** (kde and gnome only). Printing (CUPS), scanning (SANE), fingerprint (fprintd), CJK input methods (fcitx5).

## Composition

Each variant is built by listing layers in `packages/manifests/<variant>.manifest`. Layers live under `packages/layers/<family>/<layer>.txt`. Per-layer system files live under `system_files/layers/<family>/<layer>/`. See [Containerfile and packages](../../building-and-forking/containerfile-and-packages/).

## Switching between variants

Variants can be switched after install with `cache22-rebase`. The current deployment is preserved as a rollback target. See [Variant Switching](../../system-ops/rebase/).

```
sudo cache22-rebase                          # Interactive picker.
sudo cache22-rebase --variant cachy-kde
sudo cache22-rebase --reboot                 # Reboot when done.
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
