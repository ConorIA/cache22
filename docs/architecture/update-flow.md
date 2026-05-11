---
title: Update Flow
parent: Architecture
nav_order: 4
---

# Update Flow

The full update flow from staging through reboot to a working new deploy.

## Phase 1. Stage

Triggered by `cache22-update`, `bootc upgrade`, `cache22-rebase`, or `bootc switch`.

```
cache22-update
  -> bootc upgrade --check
     # Read-only check against the registry.
     # Exit if no new content.
  -> bootc upgrade
     -> bootc pulls layers from registry.
     -> bootc creates an ostree commit from the OCI image.
     -> ostree creates a deploy directory under
        /sysroot/ostree/deploy/<state>/deploy/<new-csum>.<idx>/
     -> The new deploy is in the "staged" slot.
        bootc status .status.staged != null
  -> /usr/libexec/cache22/refresh-pending-motd
     -> Reads bootc status, writes /run/motd.d/10-cache22-pending-reboot
        with a dynamic apply hint (soft-reboot vs full reboot based on
        softRebootCapable).
     -> Pops a desktop notification on graphical sessions.
  (returns)
```

At this point:

- The staged deploy directory exists on disk.
- ostree has staged metadata in `/sysroot/ostree/repo/`.
- No BLS entry is written yet. No UKI is built yet.
- The bootloader still points at the booted deploy.
- The user's existing system continues to run normally.

This is the standard bootc/ostree behavior. Finalize and UKI build are deferred to shutdown.

## Phase 2. Apply (default path: full reboot or auto-pick)

Triggered by `cache22-reboot` (no flags) or `systemctl reboot`.

```
systemctl reboot
  (or cache22-reboot which exec's systemctl reboot for the hard path)
  -> systemd shutdown sequence begins.
  -> reboot.target activates.
  -> All units with Conflicts=final.target stop.
  -> ostree-finalize-staged.service stops.
     ExecStop runs in declaration order:
       1. /usr/bin/ostree admin finalize-staged
          -> Writes BLS entry to /boot/loader/entries/.
          -> Swaps active boot.X slot.
          -> Cleans up old deploys per retention policy.
       2. /usr/libexec/cache22/resign-uki  (from 50-cache22-uki.conf drop-in)
          -> For each live deploy, build the UKI from BLS entry.
          -> Sign with per-machine SB key + tpm-pcr11.key.
          -> Atomic-write to /efi/EFI/Linux/cache22-<csum>.efi.
          -> Re-sign sd-boot if newer.
          -> GC stale UKIs.
  -> systemd-reboot.service runs.
  -> Hardware reboots.

  Boot sequence:
  -> Firmware POST.
  -> Firmware loads sd-boot (signed).
  -> sd-boot enumerates UKIs in /efi/EFI/Linux/.
  -> sd-boot picks highest .osrel VERSION_ID UKI (the new deploy).
  -> sd-stub measures PCR 11 with this UKI's content.
  -> Kernel + initramfs run.
  -> initramfs:
     -> ostree-prepare-root reads ostree= karg from cmdline.
     -> Bind-mounts the new deploy as /sysroot.tmp.
     -> Sets up /etc bind-mount (writable on top of read-only deploy).
     -> Sets up other binds (/var, /sysroot, /boot).
     -> switch_root to /sysroot.tmp (which becomes the new /).
  -> systemd starts in the new root.
  -> ostree-remount.service runs:
     -> Various /var, /sysroot remounts.
     -> 50-cache22-etc-rw.conf drop-in's ExecStartPost runs:
        -> /usr/libexec/cache22/ensure-etc-writable (no-op on hard boot
           because /etc is already RW from initrd's bind).
  -> sysinit.target reached.
  -> systemd-tmpfiles-setup, sysusers, etc., run with writable /etc.
  -> multi-user.target reached.
  -> cache22-pending-motd.service runs:
     -> Sees no staged (the previously-staged is now booted).
     -> Removes the stale MOTD marker.
  -> User can log in.
  -> 2 minutes later: cache22-healthcheck.service runs:
     -> Runs scripts in /etc/cache22/healthcheck.d/required.d/.
     -> If all pass: reset bad-boots counter.
     -> If any fail: increment counter; if counter >= 3, bootc rollback + reboot.
```

## Phase 2 alternative. soft-reboot

Triggered by `cache22-reboot` (auto-pick, when softRebootCapable=true) or `cache22-reboot --soft`.

```
cache22-reboot --soft
  -> ostree admin finalize-staged
     -> Writes BLS entry, swaps boot.X slot.
  -> /usr/libexec/cache22/resign-uki
     -> Builds UKI for the staged deploy (for future hard reboots).
  -> /usr/libexec/cache22/prepare-soft-reboot
     -> Creates /run/nextroot.
     -> Bind-mount the staged deploy directory at /run/nextroot.
     -> Bind /etc, /usr (RO), /sysroot, /boot, /efi, /var into /run/nextroot.
     -> Update /run/ostree-booted with the new deploy's dev/inode.
  -> systemctl soft-reboot
     -> systemd serializes state.
     -> Stops all units (ExecStops run; cache22 hooks are no-ops because
        prepare-soft-reboot already finalized + built UKI).
     -> Switch_root into /run/nextroot.
     -> Re-execs PID 1 (systemd) in the new root.
  -> New systemd instance starts.
  -> Normal boot sequence continues, but:
     -> Same kernel keeps running (no firmware POST, no kernel restart).
     -> /run is preserved (so /run/nextroot is now /, /run/ostree-booted is current).
     -> ostree-remount.service runs; 50-cache22-etc-rw.conf drop-in
        re-establishes /etc bind (the bind from prepare-soft-reboot was
        dropped during pivot).
     -> sysinit.target, multi-user.target, etc., proceed normally.
  -> User session resumes (SSH may briefly disconnect during pivot).
```

The whole soft-reboot completes in ~5 seconds.

## Phase 2 alternative. kexec

Triggered by `cache22-reboot --kexec` or auto-pick when `KERNEL_CHANGE_STRATEGY=kexec` and softRebootCapable=false.

```
cache22-reboot --kexec
  -> ostree admin finalize-staged
  -> /usr/libexec/cache22/resign-uki
  -> Pick the highest VERSION_ID UKI on /efi/EFI/Linux/.
  -> Extract .linux, .initrd, .cmdline from the UKI's PE sections.
  -> Re-sign the kernel with the per-machine SB key (so it works under
     kernel lockdown if enabled).
  -> kexec --load (stage the new kernel in kernel memory).
  -> systemctl kexec
     -> systemd shutdown sequence runs (ostree-finalize-staged ExecStop
        is a no-op since we already finalized; same for resign-uki).
     -> kexec_exec replaces the running kernel with the loaded one.
  -> New kernel runs initramfs.
  -> initramfs:
     -> ostree-prepare-root reads ostree= karg.
     -> Sets up the deploy and switch_roots.
  -> systemd starts in the new root.
  -> Normal boot sequence proceeds.
```

The kexec'd boot saves ~10-30 seconds compared to a full reboot (skips firmware POST). LUKS unlock requires a PCR 7 fallback keyslot to auto-unlock; otherwise the user is prompted.

## Failure handling at each step

| Step | Failure mode | Recovery |
|---|---|---|
| `bootc upgrade` | Network failure, registry unavailable. | Retry. No state change. |
| `ostree admin finalize-staged` at shutdown | ostree internal error. | Recorded in journal; system reboots without finalizing. Next reboot retries. |
| `resign-uki` at shutdown | sbsign fails, sb-key-init missing key files. | Recorded in journal; reboot proceeds. Old UKIs remain. New deploy is finalized but not bootable until the next `resign-uki` runs. |
| Boot of new deploy | Kernel panic, ostree-prepare-root failure. | sd-boot menu lets user pick the previous UKI (rollback). After 3 such cycles, `cache22-healthcheck` auto-rolls-back. |
| Health check failure | Service fails one of the configured checks. | Counter increments. After 3 consecutive failures, `bootc rollback` + reboot. |

## Idempotency

Most steps are idempotent and can be re-run:

- `ostree admin finalize-staged` is a no-op when nothing is staged.
- `resign-uki` rebuilds UKIs that already exist; the atomic-write ensures the previous UKI remains visible until the new one is fully on disk.
- `cache22-pending-motd.service` writes or removes the marker based on current state; harmless to re-run.

This idempotency is what allows triggers like `bootc-status-updated.target` to fire frequently without causing churn.

## See also

- [bootc and ostree](../bootc-and-ostree/) for the layer responsibilities.
- [Per-Deploy UKI Build](../per-deploy-uki/) for resign-uki internals.
- [Three Reboot Paths](../../updates-and-reboots/three-reboot-paths/) for the user-facing reboot strategy choice.
- [Health Checks](../../system-ops/healthcheck/) for the auto-rollback safety net.
