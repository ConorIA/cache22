---
title: bootc and ostree
parent: Architecture
nav_order: 1
---

# bootc and ostree

cache22 sits on top of two layers: ostree (the lower layer, owns deploys on disk) and bootc (the higher layer, owns container-image-to-deploy mapping).

## ostree

ostree provides:

- A content-addressable filesystem store at `/sysroot/ostree/repo/`. Files are deduplicated by SHA-256.
- Multiple deploys per machine. Each deploy is a hardlink farm referencing the repo's objects, mounted at `/sysroot/ostree/deploy/<state>/deploy/<csum>.<idx>/`.
- Slot management: booted, staged, pending, rollback. State changes happen via subcommands like `ostree admin deploy`, `ostree admin finalize-staged`, `ostree admin rollback`.
- The `ostree-prepare-root` initrd helper that bind-mounts a deploy as the new root.
- The `ostree-remount.service` that handles `/var` and `/sysroot` remounts at runtime.

ostree does NOT know about container images, registry pulls, OCI layers, or signatures. It operates on bare commits.

## bootc

bootc provides:

- Container image → ostree commit mapping. `bootc upgrade` pulls an OCI image from a registry and creates an ostree commit from it.
- Image reference tracking. `bootc status` shows which image ref the booted/staged/rollback deploys come from.
- `bootc upgrade`, `bootc switch`, `bootc rollback` as a higher-level UX over ostree's plumbing.
- Per-layer fetching with delta optimization (only changed layers are downloaded).

bootc does NOT touch the bootloader by default (cache22 uses `--bootloader=none` at install). bootc does NOT manage UKIs or per-deploy signing (cache22 owns this).

## How cache22 uses both

```
cache22-update
  -> bootc upgrade --check   # Decide if anything to do.
  -> bootc upgrade            # Pull from registry, create ostree commit, stage deploy.
  (returns)

User runs systemctl reboot or cache22-reboot
  -> shutdown sequence
    -> ostree-finalize-staged.service ExecStop
      -> ostree admin finalize-staged   # Write BLS entry, swap boot config.
      -> 50-cache22-uki.conf drop-in's ExecStop
        -> /usr/libexec/cache22/resign-uki   # Build per-deploy UKI on ESP.
    -> reboot
  -> sd-boot loads the new UKI
    -> sd-stub measures PCR 11
      -> kernel + initramfs run
        -> ostree-prepare-root binds the new deploy as root
          -> systemd starts in real root
```

ostree is the layer that actually owns the on-disk deploy state. bootc is the layer that talks to the registry and provides the user-facing commands. cache22 adds the per-deploy UKI build and signing on top.

## Where the lines are

| Operation | Layer | Note |
|---|---|---|
| Pull image from registry | bootc | bootc handles auth, layer fetch, conversion to ostree commit. |
| Create deploy directory | ostree | Hardlinked from the repo. |
| Stage / finalize / boot config | ostree | bootc invokes via `ostree-finalize-staged.service`. |
| Bind-mount root in initrd | ostree | `ostree-prepare-root`. |
| Etc / var / sysroot remounts at runtime | ostree | `ostree-remount.service`. |
| Bootloader install | cache22 | `bootctl install` + per-machine SB key setup. |
| Per-deploy UKI build + signing | cache22 | `resign-uki` triggered via drop-ins. |
| TPM2 LUKS unlock policy | cache22 + systemd | `cache22-encryption` wraps `systemd-cryptenroll`. |
| Reboot strategy decision | cache22 | `cache22-reboot` reads bootc state, picks soft/kexec/hard. |
| MOTD pending-reboot marker | cache22 | `cache22-pending-motd.service` triggered by bootc-status-updated.target. |

## Why split this way

bootc was designed to handle the registry/OCI side cleanly. ostree was designed to handle the on-disk deploy side cleanly. cache22 adds value on top of both:

- Per-machine UKI signing without a central CI key.
- A unified `cache22-reboot` that picks the fastest applicable reboot strategy.
- Health check + auto-rollback safety net.
- TPM2 LUKS unlock with a sensible default policy and an opt-in fallback for kexec.

These layers compose without modification to bootc or ostree. cache22's additions live in `system_files/` (overlay), `Containerfile` (image build), and a few systemd drop-ins (`50-cache22-uki.conf`, `50-cache22-etc-rw.conf`). No bootc or ostree fork is required.

## See also

- [Per-Deploy UKI Build](../per-deploy-uki/) for the UKI signing pipeline.
- [Update Flow](../update-flow/) for the full shutdown sequence.
- [Filesystem Layout](../filesystem-layout/) for how /var, /etc, and /usr are organized.
