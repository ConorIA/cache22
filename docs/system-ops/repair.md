---
title: Repair
parent: System Ops
nav_order: 3
---

# Repair

When the installed cache22 system will not boot, recover from the live ISO using `cache22-repair`.

## Symptoms requiring repair

- sd-boot menu shows no cache22 entry.
- sd-boot menu shows entries but firmware refuses to load any of them.
- Kernel boots but kernel panics in initramfs (e.g., LUKS not unlockable).
- Both deploys fail health checks and auto-rollback cycles indefinitely.
- Per-machine Secure Boot key on the encrypted root has been lost (e.g., key directory deleted in error).

If the system reaches a shell at all (even an emergency one), prefer fixing in place rather than running `cache22-repair`. See [Customization → bootc usroverlay](../../customization/usroverlay/) for in-place editing.

## Prerequisites

- The cache22 live ISO matching the installed variant family (cachy ↔ arch).
- The LUKS passphrase for the encrypted root (if LUKS is enabled).
- Access to the firmware setup menu.

## Procedure

### 1. Boot the live ISO

Insert the USB and boot it. The live ISO auto-logins as root on tty1.

### 2. Run cache22-repair

```
cache22-repair
```

The helper:

1. Detects existing cache22 installations on attached disks.
2. Prompts for the target install if multiple are found.
3. Prompts for the LUKS passphrase if LUKS is enabled on the target.
4. Mounts the target's root and ESP into a chroot.
5. Drops into a chroot shell with the target's filesystem available.

From the shell, repair operations can be performed: re-running `bootc upgrade`, regenerating UKIs, re-installing sd-boot, re-enrolling SB keys, etc.

### 3. Common repairs

#### Re-run bootc finalize and resign-uki

If a botched update left the system without a working UKI:

```
# Inside the chroot:
ostree admin finalize-staged
/usr/libexec/cache22/resign-uki
```

This finalizes any staged deploy and regenerates UKIs for all live deploys. Exit the chroot and reboot.

#### Re-install sd-boot

If sd-boot itself is corrupted on the ESP:

```
# Inside the chroot:
bootctl install
/usr/libexec/cache22/resign-uki
```

`bootctl install` writes an unsigned sd-boot to the ESP. `resign-uki` re-signs it with the per-machine key and reinstalls.

#### Re-enroll Secure Boot keys

If firmware reset cleared cache22's PK:

```
# Inside the chroot:
cache22-secureboot enable
```

Exit, reboot into firmware setup, put the firmware in setup mode, and reboot. sd-boot will re-enroll on the next boot.

#### Disable Secure Boot temporarily

If the SB chain is fundamentally broken and the user wants to boot without enforcement:

1. Exit the chroot. Reboot.
2. In firmware setup, disable Secure Boot.
3. Boot. cache22 runs without SB enforcement.
4. From within the booted system, re-enable SB:
   ```
   sudo cache22-secureboot enable
   sudo systemctl reboot
   ```
5. In firmware setup, put firmware in setup mode (or re-enable SB which often does this).
6. Boot again. SB chain is restored.

#### Force rollback when both deploys are broken

If both the booted and rollback deploys fail:

```
# Inside the chroot:
ostree admin status                    # See available deploys.
ostree admin set-default <csum>.<idx>  # Pick a working one.
```

Then exit and reboot.

If no deploy works, the only option is reinstall.

### 4. Exit and reboot

```
exit                # Leave the chroot.
reboot
```

Remove the live ISO USB when prompted.

## What cache22-repair changes

`cache22-repair` itself only sets up the chroot. Repair operations performed inside the chroot are what actually change state. The user is responsible for what runs.

The chroot session leaves:

- Mounts on the target's root, ESP, and per-machine key directories.
- A read-write `/etc` and `/var` of the target.
- Network access (uses the live ISO's network).

After exit, the helper unmounts everything cleanly.

## Reinstall as a last resort

If repair is not possible:

```
cache22-install
```

A full reinstall will erase the target disk (in whole-disk mode) or the chosen partition (in custom mode). Back up `/var` and `/home` data first if needed; mount the existing disk under the live ISO and copy data out before running `cache22-install`.

To preserve user data while reinstalling, install to a different partition or disk and migrate data manually. There is no in-place reinstall mode that preserves the existing root.

## See also

- [Installation](../../getting-started/installation/) for the initial install procedure.
- [cache22-secureboot](../../boot-and-security/cache22-secureboot/) for SB key management.
- [TPM and LUKS](../../boot-and-security/tpm-luks/) for re-enrolling TPM unlock after key changes.
- [Health Checks](../healthcheck/) for the auto-rollback that may avoid repair entirely.
