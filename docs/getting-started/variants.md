---
title: Variants
parent: Getting Started
nav_order: 3
---

# Variants

cache22 ships 20 variants, organised along four orthogonal dimensions:

- **Family.** `cachy` (CachyOS bore-lto kernel + repos) or `arch` (vanilla Arch + mainline `linux`).
- **Role.** `server` (headless, no GPU userland), `kde` (Plasma 6 desktop), or `gnome` (GNOME Shell desktop).
- **Gaming.** With or without Steam, gamescope, mangohud, lutris, sunshine, Xbox controller (`xone`).
- **NVIDIA.** With or without the proprietary NVIDIA driver and 32-bit userland.

The variant id encodes them as `family-role[-gaming][-nvidia]`. `gaming` does not apply to `server`.

## All published variants

| Variant | Family | Role | Gaming | NVIDIA |
| --- | --- | --- | --- | --- |
| `cachy-server` | cachy | server | no | no |
| `cachy-server-nvidia` | cachy | server | no | yes |
| `cachy-kde` | cachy | kde | no | no |
| `cachy-kde-nvidia` | cachy | kde | no | yes |
| `cachy-kde-gaming` | cachy | kde | yes | no |
| `cachy-kde-gaming-nvidia` | cachy | kde | yes | yes |
| `cachy-gnome` | cachy | gnome | no | no |
| `cachy-gnome-nvidia` | cachy | gnome | no | yes |
| `cachy-gnome-gaming` | cachy | gnome | yes | no |
| `cachy-gnome-gaming-nvidia` | cachy | gnome | yes | yes |
| `arch-server` | arch | server | no | no |
| `arch-server-nvidia` | arch | server | no | yes |
| `arch-kde` | arch | kde | no | no |
| `arch-kde-nvidia` | arch | kde | no | yes |
| `arch-kde-gaming` | arch | kde | yes | no |
| `arch-kde-gaming-nvidia` | arch | kde | yes | yes |
| `arch-gnome` | arch | gnome | no | no |
| `arch-gnome-nvidia` | arch | gnome | no | yes |
| `arch-gnome-gaming` | arch | gnome | yes | no |
| `arch-gnome-gaming-nvidia` | arch | gnome | yes | yes |

Image refs follow the pattern `ghcr.io/cmspam/cache22-<variant>:<tag>`.

## Choosing a family

**CachyOS variants** (`cachy-*`) use the [CachyOS](https://cachyos.org/) base distribution:

- BORE-LTO scheduler kernel (`linux-cachyos-bore-lto`) optimized for desktop responsiveness.
- v3 packages from CachyOS repos. Many packages rebuilt with x86-64-v3 instructions.
- Per-kernel pre-built modules for `nvidia-open`, `zfs`, and `r8125`. No DKMS rebuilds at image-build time.

**Arch variants** (`arch-*`) use the official Arch Linux base:

- Mainline `linux` kernel.
- DKMS-built modules for `nvidia-open`, `r8125`, `broadcom-wl`, `xone`. Compiled against `linux-headers` at image-build time.
- No ZFS support (ZFS is cachy-only via CachyOS's pre-built module).

## Choosing a role

**`server`.** No display manager, no Wayland or X11 stack, no desktop apps. Containers (podman, docker, distrobox, incus), libvirt+qemu, cockpit web admin. ~6 GB on disk.

**`kde`.** KDE Plasma 6 with `plasma-login-manager`, Dolphin, Konsole, Discover, Bazaar Flathub storefront, Firefox.

**`gnome`.** GNOME Shell with GDM, Nautilus, Loupe, Papers, Bazaar.

## Gaming dimension

When present, the `gaming` layer adds Steam, gamemode, mangohud, gamescope, lutris, goverlay, sunshine, Xbox controller (`xone`), and `xdg-desktop-portal-gtk`.

The SteamOS-style switchable gamescope session (`cache22-gamescope-mode`) is currently KDE-only — it writes `/etc/plasmalogin.conf.d/...` for autologin. GNOME-gaming variants ship Steam etc. but no session switcher.

## NVIDIA dimension

When present, the `nvidia` layer adds the proprietary NVIDIA driver and userland:

- `cachy-*-nvidia`: pre-built `linux-cachyos-bore-lto-nvidia-open` module.
- `arch-*-nvidia`: DKMS-built `nvidia-open-dkms`.

Both add `nvidia-utils`, `opencl-nvidia`, `libva-nvidia-driver`, `nvidia-settings`, `egl-wayland`, `nvidia-prime`, `switcheroo-control`, and the lib32 variants for Steam/Wine.

## What every variant ships

The base layer (always installed) includes:

- **GPU drivers.** Mesa (AMD, Intel, virtio). NVIDIA only if the `nvidia` dimension is present.
- **Filesystems.** ext4, xfs, btrfs, f2fs, exFAT, FAT32, NFS, SMB. ZFS on `cachy-*` only.
- **Network.** NetworkManager, OpenVPN, WireGuard, modemmanager, `r8125`.
- **Bluetooth.** bluez stack.
- **Audio.** PipeWire (with PulseAudio, JACK, ALSA shims).
- **Containers.** podman, podman-compose, docker, docker-compose, distrobox, incus, lxc.
- **Virtualization.** qemu-base, libvirt, virglrenderer, swtpm, edk2-ovmf.
- **CLI tooling.** git, openssh, rsync, jq, ripgrep, fd, fzf, btop, tmux, vim, nano, micro, fastfetch.
- **Firmware.** linux-firmware, sof-firmware, intel/amd microcode.
- **Desktop add-ons.** Printing (CUPS), scanning (SANE), fingerprint (fprintd), and CJK input methods (fcitx5) appear in the `desktop` layer, included by all `kde` and `gnome` variants.

## Composition

Each variant is built by listing layers in `packages/manifests/<variant>.manifest`. Layers live under `packages/layers/<family>/<layer>.txt`. Per-layer system files live under `system_files/layers/<family>/<layer>/`. See [Containerfile and packages](../../building-and-forking/containerfile-and-packages/).

## Switching between variants

Variants can be switched after install with `cache22-rebase`. The current deployment is preserved as a rollback target. See [Variant Switching](../../system-ops/rebase/).

```
sudo cache22-rebase                                  # Interactive picker.
sudo cache22-rebase --variant cachy-kde-gaming-nvidia
sudo cache22-rebase --reboot                         # Reboot when done.
```

## Pinning to a specific build

Each successful build pushes three tags per variant:

- `:rolling`. Moves with each build. The default tag for `cache22-update`.
- `:YYYY-MM-DD`. Per-day pointer. The latest build of that day wins if multiple succeeded.
- `:sha-<7chars>`. Immutable per-commit pointer.

To pin to a known-good build:

```
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde-gaming-nvidia:2026-05-04
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde-gaming-nvidia:sha-9065ce1
```

To return to the rolling stream:

```
sudo cache22-rebase --variant cachy-kde-gaming-nvidia
```

Available tags are listed at `https://github.com/cmspam/cache22/pkgs/container/cache22-<variant>`.
