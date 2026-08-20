---
title: Two Reboot Paths
parent: Updates and Reboots
nav_order: 1
---

# Two Reboot Paths

Most atomic distributions apply an update with a single reboot strategy: a full reboot. cache22 offers two, a full reboot and an opt-in kexec that skips firmware POST.

| Strategy | Time to apply | When usable |
| --- | --- | --- |
| **kexec** | ~10-30 seconds saved vs full reboot | Always usable when there is a staged deploy. Skips firmware POST + bootloader. |
| **Full reboot** | ~30-90 seconds | Always usable. The default. |

`cache22-reboot` (with no flags) does a full reboot by default, or kexec when opted into via `/etc/cache22/reboot.conf` or `--kexec`. Each strategy is described below.

> cache22 does not support soft-reboot (`systemctl soft-reboot`). Pivoting userspace while the kernel keeps running leaves encrypted data pools (LUKS held open by services such as incus) undetachable, and re-runs the TPM PCR measurements against a TPM whose state already survived from the previous userspace. Both hang or fail the boot. The systemd verb is masked on cache22 images so it cannot be invoked.

## kexec

**Time:** ~10-30 seconds saved compared to a full reboot. Skips firmware POST and the bootloader.

**Mechanism:** `kexec --load` loads the new kernel + initramfs + cmdline directly. `systemctl kexec` triggers a normal shutdown that ends with `kexec_exec` instead of a hardware reset.

**Survives:**
- Nothing across the kexec itself. The new kernel boots fresh and runs its own initramfs.

**Requirements:**
- Hardware that supports kexec cleanly. Some GPUs and NICs reset poorly after kexec.
- For TPM2 LUKS auto-unlock to keep working: a PCR 7 keyslot enrolled with `cache22-encryption`. See [TPM and LUKS](../../boot-and-security/tpm-luks/).

**Use cases:**
- Applying an update without waiting for firmware POST, when the hardware kexecs cleanly.

`cache22-reboot` picks kexec when `KERNEL_CHANGE_STRATEGY=kexec` is set in `/etc/cache22/reboot.conf`, or `--kexec` is passed on the command line. The default is a full reboot; kexec is opt-in.

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

To avoid that trap, `cache22-reboot` checks the root LUKS device before it kexecs. If it has no kexec-unlockable keyslot, it aborts the kexec and falls back to a full reboot (where the passphrase prompt is visible), unless `--no-fallback` is set. A keyslot is kexec-unlockable only when it binds plain PCRs with no signed PCR 11 policy: a PCR 11 only keyslot, or a combined PCR 7 + signed PCR 11 keyslot, does not qualify.

Only the root device is checked, because it is the only one that must unlock in the initramfs for the machine to boot. It is found from the kernel cmdline: `rd.luks.uuid=` names each LUKS device the initramfs unlocks before mounting root. If the cmdline has no `rd.luks.uuid=`, the root is not encrypted and kexec proceeds. Data pools are unlocked later from a keyfile on the already-mounted root and never block the boot, so they never force a fallback.

To kexec anyway and accept the passphrase prompt (for example with a serial console attached, or to blind-type the passphrase), pass `--kexec-force`, or set `KERNEL_CHANGE_STRATEGY=kexec-force` in `reboot.conf` so the automated paths (`cache22-update --reboot`, `cache22-autoreboot`) do the same.

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
- The default for applying any staged update.
- When debugging boot issues, since the full path exercises everything.
- When microcode or firmware updates need to take effect.

The shutdown sequence triggers `ostree-finalize-staged.service` (which writes the BLS entry for the staged deploy) and the `50-cache22-uki.conf` drop-in (which builds the per-deploy UKI). See [Update Flow](../../architecture/update-flow/) for details.

## Decision table

`cache22-reboot` (no flags) picks one of these outcomes:

| State | `KERNEL_CHANGE_STRATEGY` | Selected |
|---|---|---|
| Nothing staged | any | Full reboot of the currently booted deploy |
| Staged | `hard` (default) | **Full reboot** |
| Staged | `kexec` | **kexec** |

Override with explicit flags:

```
sudo cache22-reboot --kexec        # Force kexec when there is a staged deploy.
sudo cache22-reboot --kexec-force  # Force kexec even if LUKS will need a passphrase.
sudo cache22-reboot --hard         # Force full reboot.
sudo cache22-reboot --check        # Print the strategy that would run. Do not reboot.
sudo cache22-reboot --no-fallback  # Abort instead of falling back to a full reboot on failure.
```

## Examples

### Preview the strategy without rebooting

```
$ sudo cache22-reboot --check
strategy: hard - hard reboot (set KERNEL_CHANGE_STRATEGY=kexec or pass --kexec for kexec)
  staged digest:        sha256:f00e2552043fef13...
  KERNEL_CHANGE_STRATEGY: hard
```

### Default daily update apply

After `cache22-update` has staged a new image:

```
sudo cache22-reboot
```

By default this does a full reboot into the staged deploy. To skip firmware POST on capable hardware, opt into kexec (below).

### Opt into kexec for applying updates

Edit `/etc/cache22/reboot.conf`:

```
KERNEL_CHANGE_STRATEGY=kexec
```

From now on, applying a staged update uses kexec instead of a full reboot. The setting applies to `cache22-reboot`, `cache22-update --reboot`, and `cache22-autoreboot`.

If LUKS+TPM is in use, also enroll a PCR 7 keyslot first; see the LUKS+TPM caveat above.

### Force a full reboot for debugging

```
sudo cache22-reboot --hard
```

Useful when investigating boot issues. Skips the kexec fast path regardless of config.
