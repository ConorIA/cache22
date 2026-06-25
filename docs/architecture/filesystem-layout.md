---
title: Filesystem Layout
parent: Architecture
nav_order: 3
---

# Filesystem Layout

cache22 follows the bootc / ostree filesystem layout with a few cache22-specific additions.

## Top-level mounts

After boot, the visible mounts include:

| Mount | Source | Purpose |
|---|---|---|
| `/` | The booted deploy directory (read-only btrfs). | The OS image. |
| `/sysroot` | The btrfs root subvolume containing `/ostree`. | The physical root partition. |
| `/etc` | Bind-on-self of `<deploy>/etc` (read-write). | Per-machine configuration. |
| `/var` | Per-stateroot `/sysroot/ostree/deploy/<state>/var` (read-write). | Persistent runtime state. |
| `/home` | btrfs subvolume `/home` (read-write). | User home directories. |
| `/boot` | UEFI: same partition as `/`, mounted separately. BIOS: dedicated `cache22-boot` ext4 partition. | BLS entries and kernel/initramfs files (GRUB modules + `grub.cfg` on BIOS). |
| `/efi` | The ESP (FAT32). UEFI only. | sd-boot, UKIs, EFI variables. |

The root mount is read-only by design. Writes to `/usr` are blocked unless `bootc usroverlay` is active (see [usroverlay](../../customization/usroverlay/)).

## /etc handling

`/etc` is a writable bind-mount on the deploy's `/etc` directory. The deploy's `/etc` is the result of an ostree 3-way merge performed at deploy time, combining:

1. The previous deploy's `/usr/etc` (image defaults at last upgrade time).
2. The current `/etc` (user state including their changes).
3. The new deploy's `/usr/etc` (image defaults in the new image).

User changes carry forward. Image-shipped changes apply where the user has not customized. Conflicting changes typically prefer the user's version.

This merge happens at `bootc upgrade` time, not at boot time. At boot, `/etc` is just bound to the merged result.

The bind is set up by `ostree-prepare-root` in initrd on hard boot. On soft-reboot, the bind is dropped during systemd's pivot (systemd preserves only a fixed list of mounts, and `/etc` is not on it). The `50-cache22-etc-rw.conf` drop-in re-establishes the bind via `cache22-ensure-etc-writable`.

## /var per stateroot

`/var` lives at `/sysroot/ostree/deploy/<state>/var`. It is per-stateroot, not per-deploy. All deploys in the same stateroot share the same `/var`.

cache22 uses a single stateroot named `default`. All cache22 deploys (current, staged, rollback) share `/var`.

Several top-level paths are symlinks into `/var`:

| Symlink | Target |
|---|---|
| `/home` | `/var/home` |
| `/root` | `/var/roothome` |
| `/srv` | `/var/srv` |
| `/usr/local` | `/var/usrlocal` |
| `/opt` | `/var/opt` |

This is the Fedora atomic pattern. User-installed binaries in `/usr/local/bin`, third-party app installers writing to `/opt`, etc., all persist across upgrades because they live under `/var`.

## ESP layout

```
/efi/
  EFI/
    BOOT/
      BOOTX64.EFI               # Fallback bootloader (signed sd-boot copy).
    systemd/
      systemd-bootx64.efi       # Primary bootloader (signed by per-machine SB key).
    Linux/
      cache22-<csum>.efi        # Per-deploy signed UKI.
      cache22-<csum>.efi        # ...
  loader/
    loader.conf                 # sd-boot config.
    keys/
      auto/
        PK.auth                 # PK auto-enroll file.
        KEK.auth                # KEK auto-enroll file.
        db.auth                 # db auto-enroll file.
        microsoft-uefi-ca.auth  # Microsoft DB key auto-enroll file.
```

The Microsoft DB keys are bundled at install time so dual-boot Windows and signed-shim distros continue to work.

## Per-machine state

Files in `/var/lib/cache22/`:

| Path | Content |
|---|---|
| `/var/lib/cache22/sbkey/keys/PK/PK.{key,pem,der}` | Platform Key. |
| `/var/lib/cache22/sbkey/keys/KEK/KEK.{key,pem,der}` | Key Exchange Key. |
| `/var/lib/cache22/sbkey/keys/db/db.{key,pem,der}` | Secure Boot signing key. |
| `/var/lib/cache22/sbkey/tpm-pcr11.{key,pub}` | TPM PCR-policy key. |
| `/var/lib/cache22/sbkey/backup-<timestamp>/` | Backup of previous keys after `rotate-keys`. |
| `/var/lib/cache22/healthcheck/fail-counter` | Consecutive failed-boot counter (single integer). |

All under `/var/lib/cache22/` is mode 0700 root, and its contents are mode 0600 root. The directory is on the encrypted root, so at-rest the keys are protected by LUKS.

Files in `/etc/cache22/`:

| Path | Content |
|---|---|
| `/etc/cache22/extra-cmdline` | Per-machine kargs baked into UKIs. |
| `/etc/cache22/reboot.conf` | `cache22-reboot` preferences (`SOFT_REBOOT`, `KERNEL_CHANGE_STRATEGY`). |
| `/etc/cache22/autoupdate.conf` | `cache22-autoupdate` config (`APP_UPDATES`). |
| `/etc/cache22/autoreboot.conf` | `cache22-autoreboot` config (`WINDOW`, `ALLOW_ACTIVE_SESSIONS`). |
| `/etc/cache22/healthcheck.d/required.d/*` | User-defined health-check scripts. |

These are managed by their respective `cache22-*` tools, but can be edited manually.

## /sysroot

`/sysroot` is the btrfs root subvolume. It contains:

```
/sysroot/
  ostree/
    repo/                                # Object store (deduplicated content).
    deploy/
      default/                           # Stateroot.
        deploy/
          <csum>.0/                      # A deploy directory (booted, staged, or rollback).
            usr/                         # The image's /usr.
            etc/                         # The merged etc.
            ...
          <csum>.1/                      # Another deploy.
        var/                             # Per-stateroot var (shared by all deploys).
    boot.0/                              # BLS-related symlinks.
    boot.1/
    ...
  boot/                                  # /boot bind source.
  home/                                  # /home subvolume.
```

`/sysroot` is normally mounted read-only. To inspect deploys directly, read from `/sysroot/ostree/deploy/...` (root permissions required).

## Mount options

The btrfs root mount uses these options:

```
noatime,discard=async,space_cache=v2,subvolid=<id>,subvol=/root
```

`discard=async` issues TRIM commands without blocking writes. These options are baked into `/etc/cache22/extra-cmdline` as `rootflags=...`.

## Compression

Compression is not a mount option. It is set as a btrfs property (`compression=zstd:1`) on the `root` and `home` subvolumes, which gives ~30% compression on the OS and user data with negligible CPU cost.

Applying it as a property instead of a mount option keeps `compress` out of the filesystem's mountinfo. Some tools (for example Incus and podman) read mountinfo to decide whether a storage path is compressed, and skip nodatacow (`chattr +C`) on block images when it is; keeping it out of mountinfo leaves nodatacow available to workloads that want it. A subvolume created under `root` inherits its compression property, so a workload that needs nodatacow on its own subvolume should clear it there first with `chattr -c`, since nodatacow and compression are mutually exclusive on btrfs.

To change mount options, edit `/etc/cache22/extra-cmdline` and let the path watcher trigger a UKI rebuild. The new options take effect on next boot.

## See also

- [bootc and ostree](../bootc-and-ostree/) for the layer split.
- [Boot Chain](../../boot-and-security/boot-chain/) for the ESP and key paths.
- [Per-Deploy UKI Build](../per-deploy-uki/) for how /etc and /usr are reflected in the UKI.
