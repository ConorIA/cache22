---
title: TPM and LUKS
parent: Boot and Security
nav_order: 3
---

# TPM and LUKS

`cache22-encryption` manages TPM2 auto-unlock for LUKS volumes.

**UEFI only.** TPM2 PCR-based unlock depends on PCR measurements made by UEFI firmware and sd-boot/sd-stub during boot. BIOS installs cannot use TPM2 auto-unlock, and the BIOS installer path refuses LUKS entirely (GRUB's LUKS2 support is incomplete and would require a separate unencrypted `/boot`). For encrypted installs, use UEFI hardware. See [Installation → BIOS install](../../getting-started/installation/#bios-install) for the BIOS limitations summary.

## Synopsis

```
sudo cache22-encryption list
sudo cache22-encryption enroll <device>
sudo cache22-encryption remove <device>
```

## What it does

`cache22-encryption enroll` always installs a **PCR 11 signed-policy keyslot** as the main unlock method. The user is then prompted whether to also install a **PCR 7 fallback keyslot** for kexec support.

The two-keyslot decision is the most important part of using this tool. The rest of this page explains the tradeoff in detail.

## PCR 11 keyslot (always enrolled)

```
systemd-cryptenroll --tpm2-device=auto \
                    --tpm2-public-key=/var/lib/cache22/sbkey/tpm-pcr11.pub \
                    --tpm2-public-key-pcrs=11 \
                    /dev/<luks-dev>
```

PCR 11 is measured by sd-stub at boot, and represents the specific UKI being booted (kernel, initramfs, cmdline, osrel). The keyslot uses systemd's signed-policy mode: the TPM accepts any PCR 11 value for which a valid signature by the per-machine TPM PCR-policy key exists.

This means kernel updates, kernel argument changes, and image-content changes do NOT require LUKS re-enrollment. Each new UKI ships its own `.pcrsig` signed by the same key, automatically accepted by the TPM.

**Defends against:** an attacker with access to the SB signing key (db.key) attempting to plant a different boot path. For example, a Type 1 BLS entry pointing at a separately-signed kernel with arbitrary cmdline. sd-boot would load that kernel (it is db-signed), but no sd-stub would run, so PCR 11 stays at the booted UKI's value, not the attacker's. The TPM refuses to release the LUKS key.

**Tradeoff:** `cache22-reboot --kexec` will not auto-unlock LUKS. kexec also bypasses sd-stub, leaving PCR 11 unmeasured for the new UKI. The LUKS prompt appears (often invisible due to GPU re-init issues post-kexec). See the [kexec section](../../updates-and-reboots/three-reboot-paths/) for details.

## PCR 7 fallback keyslot (optional)

```
systemd-cryptenroll --tpm2-device=auto \
                    --tpm2-pcrs=7 \
                    /dev/<luks-dev>
```

PCR 7 captures Secure Boot state: which keys are enrolled in firmware DB, and which key was used to verify the loaded image. PCR 7 does not change between cache22 UKIs because they are all signed by the same per-machine db key. PCR 7 also survives kexec.

systemd-cryptsetup tries enrolled methods in order. If the PCR 11 keyslot's policy fails (kexec, or any other case where PCR 11 does not match), it falls through to the PCR 7 keyslot. PCR 7 still matches, and LUKS unlocks.

Because of this, `cache22-reboot` refuses to kexec when no PCR 7 (signed-policy-free) keyslot is enrolled, rather than booting into an often-invisible passphrase prompt. Override with `--kexec-force` or `KERNEL_CHANGE_STRATEGY=kexec-force`; see [Three Reboot Paths](../../updates-and-reboots/three-reboot-paths/).

**Tradeoff:** the Type 1 BLS-entry attack defense effectively goes away. An attacker who triggers a non-sd-stub boot path will fail PCR 11 unseal but succeed at PCR 7 unseal. This is equivalent to having only a PCR 7 keyslot enrolled.

**Re-enrollment needed after `cache22-secureboot rotate-keys`.** Rotation changes which db key signs UKIs. PCR 7 changes. The PCR 7 keyslot becomes useless until re-enrolled. The PCR 11 keyslot still works through rotation because the signed-policy approach uses the new TPM PCR-policy key embedded in fresh UKIs.

## Which to choose

Pick **no PCR 7 fallback** (PCR 11 only) if:

- The user does not use `cache22-reboot --kexec`.
- The user wants the strongest available defense against the Type 1 BLS-entry attack.
- The user is willing to type the LUKS passphrase after kexec when it does happen.

Pick **PCR 7 fallback enabled** (PCR 11 + PCR 7 dual keyslot) if:

- The user uses `cache22-reboot --kexec` regularly and wants kexec to auto-unlock.
- The user accepts that the Type 1 attack defense reduces to "an attacker would need both your db key AND your firmware in its current state". For most home use that is acceptable since the db key lives on the encrypted root (chicken-and-egg: needing LUKS unlocked to get the key that bypasses the lock).
- The user is willing to re-enroll the PCR 7 keyslot after `rotate-keys`.

## Examples

### Enroll for the first time

```
sudo cache22-encryption enroll /dev/nvme0n1p2
```

The command prompts:

```
Also enroll PCR 7 kexec fallback? [y/N]
```

Answer `y` if kexec auto-unlock is wanted. Answer `n` (default) for stricter PCR 11 only.

The command then prompts for the existing LUKS passphrase. After enrollment, reboot for the TPM unlock to take effect.

### Check current enrollment

```
sudo cache22-encryption list
```

Output:

```
==== Encrypted volumes ====
NAME           TYPE  FSTYPE       MOUNTPOINTS
nvme0n1p2      part  crypto_LUKS  
`-cache22-root crypt btrfs        /sysroot

==== TPM2 device ====
  /dev/tpm0
  /dev/tpmrm0

==== PCR 11 policy key ====
  /var/lib/cache22/sbkey/tpm-pcr11.pub
  Public-Key: (2048 bit)

==== TPM2 keyslots per LUKS device ====
  /dev/nvme0n1p2:
    PCR 11 - signed-policy (main: survives UKI updates)
    PCR 7  - kexec fallback (re-enroll after rotate-keys)
```

### Switch from PCR-11-only to PCR-11+PCR-7

```
sudo cache22-encryption remove /dev/nvme0n1p2
sudo cache22-encryption enroll /dev/nvme0n1p2
# Answer 'y' to the PCR 7 prompt this time.
```

`remove` wipes all TPM2 keyslots on the device. The subsequent `enroll` re-creates them per the new choice.

### Remove TPM unlock entirely

```
sudo cache22-encryption remove /dev/nvme0n1p2
```

The LUKS volume continues to work with the existing passphrase. Auto-unlock no longer happens.

### After cache22-secureboot rotate-keys

```
# Hard reboot first to use the freshly-enrolled SB keys.
sudo systemctl reboot
# After reboot:
sudo cache22-encryption remove /dev/nvme0n1p2
sudo cache22-encryption enroll /dev/nvme0n1p2
# Answer 'y' to PCR 7 again if previously using it.
```

The PCR 11 keyslot also needs re-enrollment because it is bound to the OLD TPM PCR-policy key. After rotation, the new key is used and the old keyslot is invalid.

## Failure modes

If TPM unseal fails at boot for any reason (firmware update changed PCR 7, SB state changed, expected UKI not present), the system falls through to the LUKS passphrase prompt. The passphrase still works. No data is lost.

To re-enroll after the underlying issue is fixed:

```
sudo cache22-encryption remove /dev/<luks-dev>
sudo cache22-encryption enroll /dev/<luks-dev>
```

Common causes of unexpected unseal failure:

- Firmware update changed enrolled keys, changing PCR 7. Affects the PCR 7 keyslot only; PCR 11 still works.
- `cache22-secureboot rotate-keys` ran. Re-enroll both keyslots.
- A different OS booted (USB recovery, dual-boot Windows update) and changed PCR 7. PCR 11 still works.
- The user upgraded to a UKI built before they enrolled the PCR 11 keyslot. PCR 11 mismatch. Should not happen for cache22 since UKI builds are signed at build time, but possible on edge cases.

## See also

- [cache22-secureboot](../cache22-secureboot/) for the SB key that signs `tpm-pcr11.key`.
- [Three Reboot Paths](../../updates-and-reboots/three-reboot-paths/) for what kexec actually does.
- [Threat Model](../threat-model/) for what the PCR 11 vs PCR 7 distinction protects against in cache22's specific design.
- [Troubleshooting](../../troubleshooting/) for "kexec gives blank screen" recovery.
