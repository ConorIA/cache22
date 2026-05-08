# cache22 installer — internals

The bootc/ostree/dracut ecosystem is built around Fedora's assumptions; several things need explicit handling on Arch/CachyOS. Read this before changing the installer or the image.

## Architecture

- Image builds run in GitHub Actions: matrix of 4 variants (cachy-kde, cachy-server, arch-kde, arch-server). cachy variants build on `cachyos/cachyos-v3`; arch variants on `archlinux:latest`. The Containerfile multi-stage build installs packages, generates initramfs, signs kernels, runs `bootc container lint`, and hand-writes the bootupd payload tree via `generate-bootupd-metadata.sh`.
- Each variant is rechunked into ~120 per-package layers via `scripts/rechunk-cache22.py`.
- Images published to `ghcr.io/cmspam/cache22-{cachy,arch}-{kde,server}:rolling`.
- Live ISO is a Fedora-44 live environment that pulls the variant image from ghcr at install time. The ISO uses a Fedora kernel (SB-bootable with default Microsoft keys); the installed system is Arch/CachyOS.
- Disk layout: ESP (512M FAT32, `/boot/efi`) + `/boot` (2G ext4 XBOOTLDR, kernels + initramfs + BLS entries + grub2 config) + root (rest minus 30G, btrfs/xfs/ext4) + scratch (30G ext4, freed back into root after install). With `--luks`, only root is encrypted; ESP and `/boot` stay unencrypted (UEFI requirement for ESP; grub needs to read `/boot` before the initramfs can unlock LUKS).

## Boot chain

```
firmware (Microsoft keys in db, factory-shipped)
  └─ /boot/efi/EFI/BOOT/BOOTX64.EFI        (Fedora's MS-signed shim — removable-media fallback)
  └─ /boot/efi/EFI/cache22/shimx64.efi     (Fedora's MS-signed shim — primary, efibootmgr)
      └─ /boot/efi/EFI/cache22/grubx64.efi (Fedora's signed grub2, Fedora CA in shim's vendor_cert)
          └─ /boot/grub2/grub.cfg           (bootupd static config; sources grub.cfg.d/*.cfg, runs blscfg)
              └─ /boot/loader/entries/*.conf (BLS Type-1)
                  └─ /boot/ostree/<deploy>/vmlinuz + initramfs
                      └─ shim_lock_verifier asks shim
                          └─ shim verifies kernel against MOK (cache22 cert)
```

Grub over systemd-boot: grub bundles its own ext4 driver and reads `/boot` directly. sd-boot only reads FAT, which would require duplicating every kernel onto the ESP. Kernels live in exactly one place.

## Install flow (high-level)

1. Boot live ISO. Connect WiFi if needed (`nmcli`).
2. Run `cache22-install`. Picks variant (interactive picker fetches `variants.json` from the repo), partitions, formats, mounts ESP at `/boot/efi` + `/boot` + root, pulls the image (~8 GB compressed), runs `bootc install to-filesystem --bootloader=grub` (which invokes `bootupctl install` — see below), writes user/hostname/locale/timezone into `<deploy>/etc/`, adds the cache22 ESP extras, runs `mokutil --import`, reclaims scratch into root.
3. Reboot. shim sees `MokListNew` non-empty → MokManager appears. User types `cache22sb`. Cert lands in `MokListRT`.
4. Second reboot: firmware → shim → grub → kernel (cache22-signed; shim verifies via MOK). initramfs unlocks LUKS if needed; `ostree-prepare-root` sets up the overlay root; main systemd boots.

## Required image-side fixes

Without each of these, install or boot fails.

### 1. Empty mount-point dirs in the image

Pacman 'files' DBs do not include directory entries, and the rechunker walks files only. Empty dirs (`/tmp`, `/var/tmp`, `/sysroot`, `/proc`, `/sys`, `/dev`, `/run`) vanish from the rechunked image entirely.

- `/tmp` missing → bootc's `findmnt` wrapper hits `ENOENT`, surfaces as `Inspecting filesystem /target: No such file or directory`.
- `/sysroot` missing → `ostree-prepare-root` cannot bind-mount the deployment; switch_root drops to dracut emergency.

**Fix:** `scripts/rechunk-cache22.py` injects these as explicit directory entries (`extra_dirs` in the leftover layer) with correct modes (`/tmp` = 1777, `/sysroot` = 0755).

### 2. ostree dracut module wants-symlink path

Upstream `50ostree` does:

    ln_r ".../ostree-prepare-root.service" \
         "${systemdsystemconfdir}/initrd-root-fs.target.wants/..."

On Fedora's dracut, `${systemdsystemconfdir}` is `/etc/systemd/system`. On Arch's dracut 110, it is unset. The wants symlink lands at `/initrd-root-fs.target.wants/...` — a path systemd does not scan. `ostree-prepare-root.service` never runs; switch_root fails.

**Fix:** `scripts/patch-ostree-dracut.sh` hard-codes `/etc/systemd/system/initrd-root-fs.target.wants/` before initramfs generation.

### 3. ostree dracut module is required

Without `add_dracutmodules+=" ostree "` in `/etc/dracut.conf.d/10-cache22.conf`, the initramfs lacks `ostree-prepare-root.service` entirely.

### 4. system_files overlay must be re-applied AFTER pacman

Some packages (notably `ostree`) overwrite directories where the overlay lives. The Containerfile applies the overlay both before and after `pacman -S`.

### 5. bootc and bootupd must be built for x86-64-v3 baseline

`cmspam/bootc-v3` builds bootc and bootupd inside a `cachyos/cachyos-v3` container on GHA (AMD EPYC runners). cachyos-v3's default makepkg uses `RUSTFLAGS="-C target-cpu=native"` / `CFLAGS="-march=native"`. The resulting binary emits AMD-only SSE4a instructions and `SIGILL`s on Intel CPUs.

**Fix:** `cmspam/bootc-v3`'s build workflow overrides to `RUSTFLAGS="-C target-cpu=x86-64-v3"` and `CFLAGS="-march=x86-64-v3 -mtune=generic"`. The same trap applies to any future custom build running on cachyos-v3 on GHA.

### 6. bootupd metadata must be hand-written

`bootupd generate-update-metadata` shells out to `rpm -q` to get package versions. cache22 is pacman-based, so this fails. `scripts/generate-bootupd-metadata.sh` constructs `/usr/lib/bootupd/updates/EFI.json` and the payload tree directly, deriving version strings from the NVR directory names under `/usr/lib/efi/`.

## Required installer-side recipe

### A. Mount propagation

- `mount --make-rshared /` on the live ISO before mounting the target. archiso defaults to private propagation; without rshared at root, per-target rshared doesn't propagate into the podman bind mount.
- Per-target rshared on `$TARGET`, `$TARGET/boot`, `$TARGET/boot/efi` so bootc's `findmnt --mountpoint /target` (run inside the container via `setns(/proc/1/root)`) sees the submounts.

### B. Partition typecodes

- p1 ESP — `ef00` (FAT32, 512M)
- p2 `/boot` — `ea00` (XBOOTLDR ext4, **label `boot`**) — kernels, initramfs, BLS entries, grub2 config
- p3 root — `8304` (Linux x86-64 root)
- p4 scratch — `8300` (generic Linux), ext4

The `/boot` label must be `boot` — grub2's static config from bootupd uses `search --label boot --set root` to locate it.

### C. bootc invocation

    bootc install to-filesystem \
        --source-imgref containers-storage:$IMAGE \
        --target-no-signature-verification \
        --generic-image \
        --stateroot default \
        --bootloader=grub \
        --karg=root=UUID=$ROOT_UUID \
        [--karg=rd.luks.uuid=... if LUKS] \
        --root-mount-spec=UUID=$ROOT_UUID \
        --skip-finalize \
        /target

Critical flags:

- `--bootloader=grub` — tells bootc to invoke `bootupctl install` (since bootupd is present in the image). bootupd copies shim + grub onto the ESP at `/EFI/cache22/`, writes the removable-media fallback at `/EFI/BOOT/BOOTX64.EFI`, writes `/boot/grub2/` static configs, writes `/boot/grub2/bootuuid.cfg`, runs efibootmgr, and creates `/boot/bootupd-state.json`. The only valid `--bootloader` values are `grub`, `systemd`, and `none`; `auto` does not exist on the bootc CLI.
- `--source-imgref containers-storage:$IMAGE` — install from local podman storage, not by re-pulling inside the container.
- `--root-mount-spec` by UUID — bootc's auto-detection via findmnt is brittle; explicit spec is stable.
- `--generic-image` — skip firmware-specific bootloader configuration.
- `--skip-finalize` — defer the final boot-entry write until after the cache22 ESP extras are in place.

We do NOT use `--composefs-backend`. The composefs strict-verity path broke on linux 7.x (kernel f77f281b6118 → bootc#2174) at "Initializing /etc and /var" with EIO. The legacy ostree backend works: composefs is still used at runtime to mount `/usr` read-only via `[composefs] enabled = true` in `prepare-root.conf`, but without verity enforcement.

### D. podman run wrapper for bootc

    podman run --rm --privileged --pid=host \
        --mount type=bind,src=$TARGET,dst=/target,bind-propagation=rshared \
        -v /dev:/dev \
        -v /var/lib/containers:/var/lib/containers \
        -v /var/tmp:/var/tmp \
        --entrypoint /usr/bin/bootc \
        $IMAGE \
        install to-filesystem ...

- `--privileged` and `--pid=host` are required for bootc to setns into PID 1's mount namespace.
- `-v /var/lib/containers` — the container needs to see the host's containers-storage at the same path.
- `-v /var/tmp` — skopeo stages large blobs in `/var/tmp`; without this the container's tmpfs fills up.

### E. ESP extras (post-bootc, `install_cache22_esp_extras()`)

After `bootc install`, these cache22-specific items are added that bootupd doesn't know about:

1. Copy `secureboot.cer` → `/boot/efi/EFI/BOOT/sbcert.der` — cache22 cert in DER form for manual MokManager "Enroll key from disk" fallback.
2. Copy `mmx64.efi` → `/boot/efi/EFI/BOOT/mmx64.efi` — when firmware falls back to the removable-media path (`/EFI/BOOT/BOOTX64.EFI`), shim looks for MokManager alongside itself. Without this copy, MOK enrollment fails via the removable-media path.
3. Create `/boot/boot → .` self-symlink — BLS entry paths are partition-relative; this lets `/boot/...`-prefixed paths resolve correctly when grub's `$root` is the `/boot` XBOOTLDR partition.
4. If no UEFI entry labelled `cache22` exists after bootupd runs, call `efibootmgr --create` pointing at `/EFI/cache22/shimx64.efi`.

### F. MOK enrollment

`queue_mok_enrollment()` runs after the ESP extras are in place:

1. `mokutil --import <cert.der>` with password `cache22sb` (set + confirm). Writes `MokListNew` in NVRAM.
2. First boot: shim sees `MokListNew` non-empty → MokManager. User picks "Enroll MOK" → "Continue" → "Yes" → types password → cert lands in `MokListRT`.
3. Subsequent boots: shim trusts the cache22 cert; cache22-signed kernels pass `shim_lock` verification.

If the password flow fails, "Enroll key from disk" + `/EFI/BOOT/sbcert.der` is the fallback.

After install, kernel updates are entirely ostree's domain. `bootc upgrade` writes new BLS entries + kernel + initramfs to `/boot/loader.X/` and `/boot/ostree/<deploy>/`, ostree atomically swaps the loader symlink, grub reads it on next boot. Bootloader binary updates are handled by `bootloader-update.service`.

### G. Writing user/hostname/locale/timezone into the deployed /etc

**THIS IS A FOOTGUN.** A find with `head -1` can pick `<deploy>/usr/etc` (the immutable image default) instead of `<deploy>/etc` (the writable per-deployment copy):

    DEPLOY_ETC=$(find $TARGET/ostree/deploy -maxdepth 5 -name etc -type d | head -1)
    # ^ NON-DETERMINISTIC — picks /usr/etc on btrfs

Writing to `/usr/etc/hostname` does nothing useful; ostree's etc-merge treats `hostname`, `machine-id`, etc. as machine-specific and does NOT propagate them from `/usr/etc` into `/etc`. Result: no `/etc/hostname` on the booted system, falls back to `cachyos` from `/etc/os-release`.

The installer uses `deploy_etc()` which searches `$TARGET/ostree/deploy` and `$TARGET/state/deploy`, filtering for paths ending in `*.0/etc` that don't go through `/usr`.

Files written:

- `$DEPLOY_ETC/hostname`
- `$DEPLOY_ETC/locale.conf` — `LANG=$LOCALE`
- `$DEPLOY_ETC/localtime` — symlink to `/usr/share/zoneinfo/$TIMEZONE`
- `$DEPLOY_ETC/passwd`, `shadow`, `group`
- `$DEPLOY_ETC/sudoers.d/10-wheel` — `%wheel ALL=(ALL:ALL) ALL`
- `$DEPLOY_ETC/fstab` — ESP mount (`UUID=$ESP_UUID /boot/efi vfat umask=0077 0 2`) and `/boot` mount
- User home: `$DEPLOY_VAR/home/$USERNAME` chowned to 1000:1000
- `$DEPLOY_ETC/subuid` + `subgid` — pre-seeded for rootless podman/distrobox/incus

### H. Scratch reclaim

In disk-scratch auto mode (when `CFG[scratch_part]` is not `tmpfs`):

    sync
    umount -R $TARGET
    parted -s $DISK rm 4
    parted -s $DISK resizepart 3 100%
    partprobe; udevadm settle; sleep 2
    [re-open LUKS if applicable]
    mount $ROOT_DEV $TARGET
    btrfs filesystem resize max $TARGET   # or xfs_growfs / resize2fs
    umount $TARGET

In tmpfs-scratch mode, root already spans the full disk; no reclaim step.

## x86-64-v3 preflight

The installer checks for `avx avx2 bmi1 bmi2 fma` in `/proc/cpuinfo` flags before proceeding. `lzcnt` and `movbe` are omitted from the check — Linux doesn't always report them by those names even on real v3 CPUs (lzcnt is sometimes reported as `abm`; movbe can be elided), which produces false-positive failures. The five checked flags are sufficient to identify the v3 baseline (Intel Haswell / AMD Excavator or newer).

## Verifying it actually boots

A successful boot shows:

    Starting OSTree Prepare OS/...
    [  OK  ] Finished OSTree Prepare OS/.
    Welcome to cache22!
    [...services...]
    cache22 login:

The `Starting OSTree Prepare OS/` line is the smoke test for the dracut wants-symlink fix: if absent, the symlink is in the wrong place.
