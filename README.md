# cache22

Immutable, atomic Linux desktop and server images built from Arch and CachyOS, delivered as OCI container images via [bootc](https://bootc-dev.github.io/bootc/). The `/usr` filesystem is read-only and signed. Updates are atomic with one-command rollback. The OS itself is a container image that can be swapped at boot.

This is not an official or supported version of Arch or CachyOS.

## Documentation

Full documentation is at **<https://cmspam.github.io/cache22/>**.

Quick links:

- [Getting Started](https://cmspam.github.io/cache22/getting-started/) for install + first-boot Secure Boot setup.
- [Updates and Reboots](https://cmspam.github.io/cache22/updates-and-reboots/) including the [three reboot paths](https://cmspam.github.io/cache22/updates-and-reboots/three-reboot-paths/) cache22 supports (soft-reboot, kexec, hard).
- [Boot and Security](https://cmspam.github.io/cache22/boot-and-security/) including [TPM and LUKS](https://cmspam.github.io/cache22/boot-and-security/tpm-luks/).
- [Troubleshooting](https://cmspam.github.io/cache22/troubleshooting/) for common problems.

## Variants

| Variant | Image | Base / kernel | Desktop |
| --- | --- | --- | --- |
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` | CachyOS, `linux-cachyos` | (headless) |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` | CachyOS, `linux-cachyos` | KDE Plasma 6 |
| `cachy-gnome` | `ghcr.io/cmspam/cache22-cachy-gnome:rolling` | CachyOS, `linux-cachyos` | GNOME Shell |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` | Vanilla Arch, mainline `linux` | (headless) |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` | Vanilla Arch, mainline `linux` | KDE Plasma 6 |
| `arch-gnome` | `ghcr.io/cmspam/cache22-arch-gnome:rolling` | Vanilla Arch, mainline `linux` | GNOME Shell |

All variants ship with NVIDIA (open driver), AMD, and Intel GPU support; ZFS (cachy variants only); Realtek 2.5G; Bluetooth; CUPS; SANE; fingerprint readers; CJK input via fcitx5; QEMU + libvirt + virt-manager; podman + docker + distrobox + incus.

Desktop variants (`*-kde`, `*-gnome`) additionally include Steam, Lutris, gamemode, MangoHud, gamescope, and Sunshine. KDE variants also get a SteamOS-style "gamescope mode" toggle (KDE-only because it autologin-coupled with `plasma-login-manager`).

For details on each variant see [Variants](https://cmspam.github.io/cache22/getting-started/variants/).

## Quick install

### From USB (bare metal, BIOS or UEFI)

1. Download the latest ISO from [Releases](https://github.com/cmspam/cache22/releases/latest). The ISO is a hybrid that boots on both legacy BIOS and UEFI hardware.
2. Write to USB: `sudo dd if=cache22-installer-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`.
3. Boot the USB. Run `cache22-install`. It auto-detects the firmware mode.
4. (UEFI only) Before the first reboot of the installed system, put firmware in setup mode (disable Secure Boot or clear the Platform Key). See [First-Boot Secure Boot Setup](https://cmspam.github.io/cache22/getting-started/secure-boot-first-boot/). BIOS installs skip this step — Secure Boot, signed UKIs, and TPM2 LUKS unlock are all UEFI features.

### On a VPS without ISO mount

For VPS providers that don't let you mount a custom ISO, kexec into a NixOS-based installer environment from the existing OS:

```
curl -fsSL https://raw.githubusercontent.com/cmspam/cache22/main/installer/cache22-vps-install.sh | sudo bash
```

After the kexec, SSH back in as root and run `cache22-install`. Works on both BIOS and UEFI VPSes. See [Installation → VPS via kexec](https://cmspam.github.io/cache22/getting-started/installation/#alternative-install-on-a-vps-via-kexec-no-iso-mount-needed).

## Helper commands

| Command | Purpose |
| --- | --- |
| [`cache22-update`](https://cmspam.github.io/cache22/updates-and-reboots/cache22-update/) | Recommended upgrade frontend. Pull + stage. Optional `--reboot` and `--app-updates`. |
| [`cache22-reboot`](https://cmspam.github.io/cache22/updates-and-reboots/cache22-reboot/) | Apply a staged update. Auto-picks soft-reboot, kexec, or full reboot. |
| [`cache22-autoupdate`](https://cmspam.github.io/cache22/updates-and-reboots/auto-update-and-reboot/) | Schedule unattended `cache22-update`. |
| [`cache22-autoreboot`](https://cmspam.github.io/cache22/updates-and-reboots/auto-update-and-reboot/) | Schedule unattended reboots after autoupdate. |
| [`cache22-changelog`](https://cmspam.github.io/cache22/updates-and-reboots/changelog/) | Show package-level diff between booted and staged. |
| [`cache22-rebase`](https://cmspam.github.io/cache22/system-ops/rebase/) | Switch between cache22 variants or pin to specific images. |
| [`cache22-secureboot`](https://cmspam.github.io/cache22/boot-and-security/cache22-secureboot/) | Manage the per-machine SB key and firmware DB enrollment. |
| [`cache22-encryption`](https://cmspam.github.io/cache22/boot-and-security/tpm-luks/) | TPM2 auto-unlock for LUKS. PCR 11 + optional PCR 7 fallback. |
| [`cache22-karg`](https://cmspam.github.io/cache22/customization/kernel-args/) | Manage persistent kernel command-line args. |
| [`cache22-shell`](https://cmspam.github.io/cache22/customization/distrobox/) | Open a CachyOS distrobox container for non-immutable package work. |
| [`cache22-healthcheck`](https://cmspam.github.io/cache22/system-ops/healthcheck/) | Auto-rollback after 3 consecutive bad boots. |
| [`cache22-gamescope-mode`](https://cmspam.github.io/cache22/customization/gamescope-mode/) | (KDE variants only) Toggle SteamOS-style gamescope autologin. |

## Forking

To build your own variant: fork this repository, edit `packages/`, `system_files/`, or the Containerfile, and push. GitHub Actions builds and publishes to `ghcr.io/<your-username>/cache22-<variant>:rolling` automatically. No CI signing key configuration is needed (cache22 uses per-machine signing). See [Forking](https://cmspam.github.io/cache22/building-and-forking/forking/).

## License

Apache 2.0 for build scripts and tooling. Packaged software keeps its own licenses.

## Acknowledgements

[CachyOS](https://cachyos.org/) for the base distro and v3-optimized packages. [bootc](https://github.com/bootc-dev/bootc) and the broader ostree/composefs ecosystem. [bootcrew/mono](https://github.com/bootcrew/mono) for path-finding bootc-on-Arch ideas. [Universal Blue](https://universal-blue.org/) and [Bazzite](https://bazzite.gg/) for the multi-variant Containerfile pattern.
