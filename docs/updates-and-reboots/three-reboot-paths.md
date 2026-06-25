---
title: Three Reboot Paths
parent: Updates and Reboots
nav_order: 1
---

# Three Reboot Paths

Most atomic distributions apply an update with a single reboot strategy: a full reboot. cache22 ships three.

| Strategy | Time to apply | When usable |
| --- | --- | --- |
| **Soft-reboot** | ~5 seconds | Staged deploy has the same kernel + initramfs as booted. |
| **kexec** | ~10-30 seconds saved vs full reboot | Always usable when there is a staged deploy. Skips firmware POST + bootloader. |
| **Full reboot** | ~30-90 seconds | Always usable. Required when nothing fast is possible or appropriate. |

`cache22-reboot` (with no flags) picks the fastest safe option based on bootc state and `/etc/cache22/reboot.conf`. Each strategy is described below.

## Soft-reboot

**Time:** ~5 seconds.

**Mechanism:** `systemctl soft-reboot` switches root into the staged deploy's filesystem without restarting the kernel. The running kernel keeps its in-memory state. Userspace re-initializes against the new root.

**Survives:**
- Kernel uptime continues; `uptime(1)` does not reset.
- Open TCP connections survive briefly during the pivot (mostly useful for SSH sessions that re-establish quickly).
- `/run`, `/tmp`, `/var/log/journal`, `/sysroot`, `/home`, `/var`, `/boot`, `/efi`, `/usr/lib/modules` are preserved.

**Requirements:**
- `bootc status` reports `softRebootCapable: true` for the staged deploy. This requires the staged deploy's kernel and initramfs to be byte-identical to the booted one. In practice, this means the update did not change the kernel package or initramfs generation.

**Use cases:**
- Userspace-only updates (most daily updates when the kernel package is unchanged).
- Same-content re-stages (e.g., `bootc switch` to the current digest).

`cache22-reboot` picks soft-reboot automatically when `softRebootCapable=true` and `SOFT_REBOOT=auto` in `/etc/cache22/reboot.conf` (the default). To opt out, set `SOFT_REBOOT=never` in the config.

### How cache22 implements soft-reboot

ostree's `ostree admin prepare-soft-reboot` requires the composefs runtime backend. cache22 uses the legacy ostree backend, so it does not call that command. Instead, `cache22-reboot` runs `/usr/libexec/cache22/prepare-soft-reboot` which mirrors what `ostree-prepare-root` does in initrd for the legacy backend: bind-mount the deploy at `/run/nextroot`, set up `/etc`, `/usr` (read-only), `/sysroot`, `/boot`, `/efi`, and `/var` (per-stateroot), then trigger `systemctl soft-reboot`.

See [Boot Chain](../../boot-and-security/boot-chain/) and [Update Flow](../../architecture/update-flow/) for the full sequence.

## kexec

**Time:** ~10-30 seconds saved compared to a full reboot. Skips firmware POST and the bootloader.

**Mechanism:** `kexec --load` loads the new kernel + initramfs + cmdline directly. `systemctl kexec` triggers a normal shutdown that ends with `kexec_exec` instead of a hardware reset.

**Survives:**
- Nothing across the kexec itself. The new kernel boots fresh and runs its own initramfs.

**Requirements:**
- Hardware that supports kexec cleanly. Some GPUs and NICs reset poorly after kexec.
- For TPM2 LUKS auto-unlock to keep working: a PCR 7 keyslot enrolled with `cache22-encryption`. See [TPM and LUKS](../../boot-and-security/tpm-luks/).

**Use cases:**
- Kernel updates where soft-reboot is not possible but the user wants to avoid firmware POST time.

`cache22-reboot` picks kexec when:

- The staged deploy is not soft-reboot capable (kernel changed), AND
- `KERNEL_CHANGE_STRATEGY=kexec` is set in `/etc/cache22/reboot.conf`, OR `--kexec` is passed on the command line.

The default for kernel-changing updates is full reboot, not kexec. kexec is opt-in.

### How cache22 implements kexec

`cache22-reboot --kexec`:

1. Calls `ostree admin finalize-staged` to write the BLS entry for the staged deploy.
2. Calls `/usr/libexec/cache22/resign-uki` to build and sign the per-deploy UKI on the ESP.
3. Picks the UKI sd-boot would auto-default to (highest `.osrel VERSION_ID`).
4. Extracts the kernel, initramfs, and cmdline from the signed UKI's PE sections.
5. Re-signs the kernel with the per-machine SB key (so it works under kernel lockdown if enabled).
6. Calls `kexec --load` to stage the new kernel.
7. Calls `systemctl kexec` to trigger the clean shutdown + kexec transition.

### LUKS+TPM caveat

When LUKS is configured for TPM2 auto-unlock with a PCR 11 signed-policy keyslot (the default), kexec breaks auto-unlock. PCR 11 is measured by sd-stub at boot. kexec bypasses sd-stub, so PCR 11 stays at the booted UKI's value, not the kexec'd one. The TPM refuses to release the LUKS key. The kexec'd kernel would then reach the LUKS prompt, which may not be visible (GPU re-init after kexec frequently leaves the screen blank until a later mode change).

To avoid that trap, `cache22-reboot` checks the boot LUKS before it kexecs. If no kexec-unlockable keyslot is enrolled, it aborts the kexec and falls back to a full reboot (where the passphrase prompt is visible), unless `--no-fallback` is set. A keyslot is kexec-unlockable only when it binds plain PCRs with no signed PCR 11 policy: a PCR 11 only keyslot, or a combined PCR 7 + signed PCR 11 keyslot, does not qualify.

To enable kexec auto-unlock, enroll a PCR 7 fallback keyslot. PCR 7 captures Secure Boot state, which does not change between cache22 UKIs signed by the same key, and it survives kexec.

```
sudo cache22-encryption enroll /dev/<luks-dev>     # When prompted, answer 'y' to PCR 7.
```

See [TPM and LUKS](../../boot-and-security/tpm-luks/) for the security tradeoff.

## Full reboot

**Time:** ~30-90 seconds depending on firmware POST time.

**Mechanism:** `systemctl reboot`. Full firmware POST, bootloader, kernel boot, initramfs, switch_root, userspace startup.

**Survives:**
- Nothing across the reboot.

**Requirements:**
- Always available.

**Use cases:**
- Default when no fast path is possible or opted-into.
- When debugging boot issues, since the full path exercises everything.
- When microcode or firmware updates need to take effect.

The shutdown sequence triggers `ostree-finalize-staged.service` (which writes the BLS entry for the staged deploy) and the `50-cache22-uki.conf` drop-in (which builds the per-deploy UKI). See [Update Flow](../../architecture/update-flow/) for details.

## Decision table

`cache22-reboot` (no flags) picks one of these outcomes:

| State | `softRebootCapable` | `KERNEL_CHANGE_STRATEGY` | Selected |
|---|---|---|---|
| Nothing staged | n/a | n/a | Full reboot of the currently booted deploy |
| Staged, same kernel | `true` | n/a | **Soft-reboot** |
| Staged, kernel changed | `false` | `hard` (default) | **Full reboot** |
| Staged, kernel changed | `false` | `kexec` | **kexec** |

Override with explicit flags:

```
sudo cache22-reboot --soft         # Force soft-reboot. Errors if not capable (unless --no-fallback omitted).
sudo cache22-reboot --kexec        # Force kexec when there is a staged deploy.
sudo cache22-reboot --hard         # Force full reboot.
sudo cache22-reboot --check        # Print the strategy that would run. Do not reboot.
sudo cache22-reboot --no-fallback  # Abort instead of falling back to a full reboot on failure.
```

## Examples

### Preview the strategy without rebooting

```
$ sudo cache22-reboot --check
strategy: soft - soft-reboot (kernel unchanged, fastest)
  staged digest:        sha256:f00e2552043fef13...
  softRebootCapable:    true
  KERNEL_CHANGE_STRATEGY: hard
  SOFT_REBOOT:            auto
```

### Default daily update apply

After `cache22-update` has staged a new image:

```
sudo cache22-reboot
```

If the kernel did not change, this completes in about 5 seconds and your SSH session may even survive the pivot. If the kernel changed, the default full reboot fires.

### Opt into kexec for kernel-changing updates

Edit `/etc/cache22/reboot.conf`:

```
KERNEL_CHANGE_STRATEGY=kexec
```

From now on, kernel-changing updates use kexec instead of full reboot. The setting applies to `cache22-reboot`, `cache22-update --reboot`, and `cache22-autoreboot`.

If LUKS+TPM is in use, also enroll a PCR 7 keyslot first; see the LUKS+TPM caveat above.

### Force a full reboot for debugging

```
sudo cache22-reboot --hard
```

Useful when investigating boot issues. Skips both the soft-reboot and kexec fast paths regardless of state.

### Trigger soft-reboot of an already-applied deploy

Re-stage the current image at its exact digest, then soft-reboot:

```
DIGEST=$(sudo bootc status --json | jq -r .status.booted.image.imageDigest)
sudo bootc switch --transport registry "ghcr.io/cmspam/cache22-cachy-server@$DIGEST"
sudo cache22-reboot
```

The "update" is a no-op (same content), but the soft-reboot exercises the pivot mechanism. Useful for testing.
