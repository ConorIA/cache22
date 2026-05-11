---
title: Home
nav_order: 1
permalink: /
---

# cache22

Immutable, atomic Linux desktop and server images built from Arch and CachyOS, delivered as OCI container images via [bootc](https://bootc-dev.github.io/bootc/). The `/usr` filesystem is read-only and signed. Updates are atomic with one-command rollback. The OS itself is a container image that can be swapped at boot.

This is not an official or supported version of Arch or CachyOS.

## Variants

| Variant | Image | Base / kernel | Desktop |
| --- | --- | --- | --- |
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` | CachyOS, `linux-cachyos-bore-lto` | (headless) |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` | CachyOS, `linux-cachyos-bore-lto` | KDE Plasma 6 |
| `cachy-gnome` | `ghcr.io/cmspam/cache22-cachy-gnome:rolling` | CachyOS, `linux-cachyos-bore-lto` | GNOME Shell |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` | Vanilla Arch, mainline `linux` | (headless) |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` | Vanilla Arch, mainline `linux` | KDE Plasma 6 |
| `arch-gnome` | `ghcr.io/cmspam/cache22-arch-gnome:rolling` | Vanilla Arch, mainline `linux` | GNOME Shell |

All variants ship with NVIDIA (open driver), AMD, and Intel GPU support; ZFS (cachy variants only); Realtek 2.5G (`r8125`); Bluetooth; printing (CUPS); SANE; fingerprint readers; CJK input via fcitx5; QEMU + libvirt + virt-manager; podman + docker + distrobox + incus.

Desktop variants (`*-kde`, `*-gnome`) additionally include Steam, Lutris, gamemode, MangoHud, gamescope, and Sunshine. KDE variants also get a SteamOS-style "gamescope mode" toggle (KDE-only because it autologin-couples with `plasma-login-manager`).

## Notable features

**Two fast paths for applying updates.** `cache22-reboot` selects between three reboot strategies based on what bootc reports about the staged deploy: soft-reboot (~5 sec, kernel keeps running, network connections survive), kexec (~10-30 sec faster than a full reboot when the kernel changed), or full reboot. See [Three Reboot Paths](./updates-and-reboots/three-reboot-paths/).

**Per-machine Secure Boot signing.** Each install generates its own SB key locally. UKIs are signed on the user's machine. There is no central CI signing key. See [Boot Chain](./boot-and-security/boot-chain/).

**TPM2 LUKS auto-unlock with two keyslot options.** PCR 11 signed-policy keyslot (always) survives every UKI rebuild without re-enrollment. Optional PCR 7 keyslot (opt-in) lets `cache22-reboot --kexec` auto-unlock too. See [TPM and LUKS](./boot-and-security/tpm-luks/).

**One-command rollback and auto-rollback on failure.** `sudo bootc rollback && sudo systemctl reboot` reverts to the previous deployment. Health checks 2 minutes after every boot trigger an automatic rollback after 3 consecutive failures. See [Health Checks](./system-ops/healthcheck/).

**Per-package layer rechunking for small daily upgrades.** Typical daily upgrades download only the layers whose contents actually changed (~100-300 MB), not the full multi-GB image. See [Architecture](./architecture/).

## Sections

1. [Getting Started](./getting-started/). Install, first-boot Secure Boot setup, picking a variant.
2. [Updates and Reboots](./updates-and-reboots/). `cache22-update`, the three reboot paths, auto-update, pinning to specific builds.
3. [Boot and Security](./boot-and-security/). sd-boot + UKI architecture, TPM2 LUKS unlock, Secure Boot key management.
4. [Customization](./customization/). Kernel args, distrobox, Flatpak, temporary writable `/usr`.
5. [System Ops](./system-ops/). Variant switching, health checks, repair from live ISO.
6. [Architecture](./architecture/). bootc + ostree internals, build pipeline, per-deploy UKI build.
7. [Building and Forking](./building-and-forking/). Fork the repo, customize packages and overlays.
8. [Troubleshooting](./troubleshooting/). Common problems and how to fix them.

## Acknowledgements

[CachyOS](https://cachyos.org/) for the base distro and v3-optimized packages. [bootc](https://github.com/bootc-dev/bootc) and the broader ostree/composefs ecosystem. [bootcrew/mono](https://github.com/bootcrew/mono) for path-finding bootc-on-Arch ideas. [Universal Blue](https://universal-blue.org/) and [Bazzite](https://bazzite.gg/) for the multi-variant Containerfile pattern.

Apache 2.0 for build scripts and tooling. Packaged software keeps its own licenses.
