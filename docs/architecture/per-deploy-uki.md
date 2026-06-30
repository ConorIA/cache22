---
title: Per-Deploy UKI Build
parent: Architecture
nav_order: 2
---

# Per-Deploy UKI Build

Each cache22 deploy gets its own signed Unified Kernel Image (UKI) on the ESP. The build runs on the user's machine, signed by the per-machine Secure Boot key.

## Where UKIs live

```
/efi/EFI/Linux/cache22-<bootcsum>.efi
```

`<bootcsum>` is a 16-character hex prefix derived from the deploy's kernel content hash. One UKI per live deploy.

Example with three deploys (booted, staged, rollback):

```
/efi/EFI/Linux/cache22-3ac96630efgh1234.efi
/efi/EFI/Linux/cache22-5eb1a5a249567890.efi
/efi/EFI/Linux/cache22-7f8d92ba01abcdef.efi
```

sd-boot enumerates UKIs from this directory. The one with the highest `.osrel VERSION_ID` is the auto-default.

## resign-uki

`/usr/libexec/cache22/resign-uki` is the script that builds UKIs.

For each live deploy, it:

1. Reads the BLS entry that ostree wrote at finalize time. The BLS entry contains the kernel path, initramfs path, and base cmdline (including the `ostree=...` argument).
2. Appends per-machine kargs from `/etc/cache22/extra-cmdline`.
3. Invokes `systemd-ukify` (`ukify build`) to assemble the UKI from kernel + initramfs + cmdline + osrel + pcrsig sections.
4. Signs the resulting UKI with the per-machine SB key (`/var/lib/cache22/sbkey/keys/db/db.key`).
5. Atomically writes the result to `/efi/EFI/Linux/cache22-<bootcsum>.efi`.

After all UKIs are built, `resign-uki`:

6. Re-signs and re-installs sd-boot if `/usr/lib/systemd/boot/efi/systemd-bootx64.efi` is newer than the on-ESP copy.
7. Garbage-collects UKIs on the ESP that do not correspond to a live deploy. GC runs only after all desired UKIs are confirmed present, so a partial failure never deletes a working UKI.

## User img per deploy

When `/etc/dracut.conf.d/` overrides exist, `resign-uki` builds the per-machine user img for each deploy in that deploy's own context: directly for the deploy it can build in context (the running deploy, or the one being staged at finalize), and by chrooting into the deploy otherwise. The build therefore always uses that deploy's own kernel modules and its own `/etc/dracut.conf.d`, never another deploy's.

The in-context deploy is rebuilt on every run, so a changed config or source is picked up rather than a stale img reused; other deploys are built only when their img is missing, since their `/etc` is frozen. Each build writes to a temp file and renames it into `/var/lib/cache22/initramfs/user-<kver>.img`, so a failed rebuild never replaces a working img. The result is folded into that deploy's UKI in place of the base img.

Because `/etc` is merged forward by ostree, an override applies to the current deploy and to every deploy created afterward. A deploy that predates the override keeps the base img. If a per-deploy build fails it falls back to the base img, so the deploy still boots.

## Triggers

`resign-uki` runs from these triggers:

| Trigger | When |
|---|---|
| `ostree-finalize-staged.service` ExecStop (via `50-cache22-uki.conf` drop-in) | Shutdown, after ostree finalizes the staged deploy. The default path for normal updates. |
| `cache22-resign-uki.path` watcher on `/etc/cache22/extra-cmdline` | When kargs are edited. Triggers a runtime rebuild for all live deploys. |
| `cache22-resign-uki.path` watcher on `/boot/loader` | When the deployment set changes while the system is running: `ostree admin undeploy`, `bootc switch`, `bootc rollback`. ostree swaps the `loader.N` symlink on every write, so this catches an undeploy that the finalize-staged drop-in (staged deploys only) misses. Without it, an undeploy leaves stale UKIs whose `boot.X` no longer resolves. |
| `cache22-reboot --soft` direct call | Before soft-reboot triggers, so the UKI for the staged deploy exists in case of a future hard reboot. |
| `cache22-reboot --kexec` direct call | Before kexec, so the kernel can be extracted from the freshly-built UKI. |
| Manual `sudo systemctl start cache22-resign-uki.service` | On demand. |

## The drop-in pattern

cache22 extends two upstream ostree services via drop-ins instead of standalone services:

- `/usr/lib/systemd/system/ostree-finalize-staged.service.d/50-cache22-uki.conf`. Adds an `ExecStop=/usr/libexec/cache22/resign-uki` line. Runs in the same systemd job as `ostree admin finalize-staged`, ordered after it. Inherits all of finalize-staged's ordering, including blocking shutdown until the UKI is built.

- `/usr/lib/systemd/system/ostree-remount.service.d/50-cache22-etc-rw.conf`. Adds an `ExecStartPost=/usr/libexec/cache22/ensure-etc-writable` line. Ensures `/etc` is a writable bind in case the bind was dropped by systemd during a soft-reboot pivot.

The drop-in pattern means cache22 inherits the parent unit's ordering, failure semantics, and shutdown-blocking behavior automatically. No standalone unit needed.

## Cmdline assembly

The cmdline baked into each UKI is the concatenation of:

1. Image-default kargs from `/usr/lib/bootc/kargs.d/*.toml` in the deploy.
2. Per-machine kargs from `/etc/cache22/extra-cmdline`.
3. The deploy-specific `ostree=/ostree/boot.<X>/<state>/<csum>/0` argument added by `resign-uki`.

The `ostree=...` argument's `boot.<X>` index is the active boot slot, which is set by `ostree admin finalize-staged`. This is why `resign-uki` runs AFTER finalize-staged: it needs the BLS entry to know which boot.X the deploy was finalized into.

If a UKI was built before finalize, the cmdline would have the WRONG boot.X (would point at the previously-active slot). The kernel would fail to mount the deploy and panic in the initramfs.

## Stale boot.X recovery (cache22-bootheal)

The `boot.X` index is the one volatile part of the baked cmdline. Any
`ostree_sysroot_write_deployments` flips it, including `ostree admin
undeploy`. The triggers above rebuild the UKIs after such a change, but a
UKI that was already booted, or one written by an older tool, can still
carry a `boot.X` that no longer resolves. On its own that is a drop to the
emergency shell.

The `cache22-bootheal` dracut module closes this. It installs a oneshot
service into the initramfs, ordered `After=sysroot.mount` and
`Before=ostree-prepare-root.service`. The service reads the `ostree=`
argument from the kernel cmdline and, only if `/sysroot/<ostree path>`
does not resolve, repoints the stale `/sysroot/ostree/boot.<X>` symlink at
the live generation directory (`/ostree/boot.<X>.<Y>`) that still contains
the deployment. The `<state>/<csum>/<serial>` tail is unaffected by an
undeploy (ostree does not renumber surviving deployments), so the survivor
boots.

On a healthy boot the `ostree=` path resolves and the service is a strict
no-op, so it cannot affect normal boot. The module ships in the initramfs
via `add_dracutmodules+=" cache22-bootheal "` in
`/usr/lib/dracut/dracut.conf.d/10-cache22.conf`.

## Signing chain

Each UKI carries TWO signatures:

- **PE signature** by the SB signing key (`db.key`). Verified by firmware against the enrolled DB. Required for sd-boot to load the UKI.
- **`.pcrsig` signature** by the TPM PCR-policy key (`tpm-pcr11.key`). The .pcrsig section is itself a JSON payload of predicted PCR 11 values, signed by `tpm-pcr11.key`. Verified by the TPM at unseal time.

Both keys are per-machine, generated at install time. Both live on the encrypted root.

## Atomicity

The ESP is FAT32 with no journaling. To handle partial writes, `resign-uki`:

- Writes each UKI to `<dst>.tmp.<pid>` first.
- `sync -f <dst>.tmp.<pid>` to flush.
- `mv -f <dst>.tmp.<pid> <dst>` to atomically rename.

Then GC removes any UKI not in the keep set, but only after every desired UKI is verified present on disk.

If any step fails partway, the previous valid UKIs remain in place. The next boot may use slightly stale UKIs but will still boot.

## Build performance

A single UKI build (kernel signing + ukify + sbsign + atomic write) takes ~1-3 seconds on a modern SSD. With three live deploys (booted + staged + rollback), the full `resign-uki` run is ~5-10 seconds. When `/etc/dracut.conf.d/` overrides exist, the in-context deploy also runs dracut on every invocation (its user img is rebuilt to pick up changes), adding roughly ten seconds; other deploys reuse their img unless it is missing, in which case a non-running deploy is built inside a chroot.

The shutdown-time invocation extends shutdown by this amount. `TimeoutStopSec=10m` in the drop-in allows ample headroom.

For runtime invocations (kargs edit, manual trigger), the build runs in the background; the shell command returns immediately if invoked via `systemctl start --no-block`.

## See also

- [Boot Chain](../../boot-and-security/boot-chain/) for how UKIs are loaded.
- [cache22-secureboot](../../boot-and-security/cache22-secureboot/) for the keys involved.
- [Update Flow](../update-flow/) for the full shutdown sequence.
- [Kernel Args](../../customization/kernel-args/) for the `extra-cmdline` source.
