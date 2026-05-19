---
title: cache22-secureboot
parent: Boot and Security
nav_order: 2
---

# cache22-secureboot

`cache22-secureboot` manages the per-machine Secure Boot key and firmware DB enrollment.

**UEFI only.** The command refuses to run on a BIOS install (no firmware Secure Boot mechanism to interact with, no ESP, no UKI to sign). If your install is on legacy BIOS hardware, this page does not apply. See [Installation → BIOS install](../../getting-started/installation/#bios-install) for the BIOS boot chain.

## Synopsis

```
sudo cache22-secureboot status
sudo cache22-secureboot enable
sudo cache22-secureboot disable
sudo cache22-secureboot rotate-keys
```

## Subcommands

### status

```
sudo cache22-secureboot status
```

Reports current state:

```
Secure Boot:           Enabled (enforcing)
Setup mode:            No
Platform key fingerprint: 7c:9f:01:b3:...
Latest signed UKI:     /efi/EFI/Linux/cache22-3ac96630.efi
sd-boot signed:        yes
Microsoft DB keys:     enrolled
```

If Secure Boot is reported as `Disabled`, either it was never enrolled (firmware was not in setup mode at first boot) or it was disabled later in firmware setup.

If Setup mode is `Yes`, the firmware is ready to accept new keys but enrollment has not run. Reboot to trigger sd-boot's auto-enrollment.

### enable

```
sudo cache22-secureboot enable
```

Idempotent setup of the per-machine SB key infrastructure:

1. Generate the SB key (`PK`, `KEK`, `db`) and TPM PCR-policy key if missing.
2. Stage auto-enroll files at `/efi/loader/keys/auto/*.auth` for sd-boot to pick up on next boot.
3. Confirm `secure-boot-enroll = force` in `/efi/loader/loader.conf`.
4. Trigger a UKI re-sign so the current UKI is signed by the new key.

After running this, the user must put the firmware in setup mode and reboot for the enrollment to take effect. See [First-Boot Secure Boot Setup](../../getting-started/secure-boot-first-boot/) for the firmware procedure.

`enable` is what `cache22-install` calls during install. Run it manually only when:

- Recovering from key loss (e.g., the encrypted root was reformatted but the user wants to set up SB again).
- Re-enrolling after firmware reset cleared the cache22 PK.

### disable

```
sudo cache22-secureboot disable
```

Removes cache22's PK, KEK, and db from the firmware database. Microsoft DB keys are kept by default so signed-shim distros and Windows continue to boot.

This requires the firmware to be in user mode with a working signing key (since modifying db requires PK signature). The command attempts to invoke the removal via `sbctl reset --partial`.

To also remove Microsoft keys (loss of Windows dual-boot, loss of most signed-shim distros):

```
sudo cache22-secureboot disable --remove-microsoft
```

After `disable`, the system can still boot cache22 but UKIs are no longer verified. To re-enable, run `cache22-secureboot enable` and re-do the firmware setup-mode procedure.

### rotate-keys

```
sudo cache22-secureboot rotate-keys
```

Generates fresh SB keys, re-enrolls them in firmware, re-signs all UKIs, and re-seals the TPM2 LUKS keyslot bound to the new TPM PCR-policy key.

Steps performed:

1. Back up existing keys to `/var/lib/cache22/sbkey/backup-<timestamp>/`.
2. Generate fresh PK, KEK, db, and TPM PCR-policy keys.
3. Stage new auto-enroll files at `/efi/loader/keys/auto/`.
4. Re-sign sd-boot and all UKIs with the new SB key.
5. Re-sign each UKI's `.pcrsig` with the new TPM PCR-policy key.

After rotate-keys:

- The firmware will refuse to load the re-signed UKIs until the new keys are enrolled. Put the firmware in setup mode and reboot to trigger re-enrollment.
- TPM2 LUKS auto-unlock may or may not need re-enrollment. The PCR 11 signed-policy keyslot survives because the new `.pcrsig` is signed by the new TPM key, but the existing keyslot was bound to the OLD TPM key's pubkey. Re-enroll the PCR 11 keyslot:

  ```
  sudo cache22-encryption remove /dev/<luks-dev>
  sudo cache22-encryption enroll /dev/<luks-dev>
  ```

- A PCR 7 fallback keyslot, if previously enrolled, is invalidated by `rotate-keys` (PCR 7 changes when the firmware-enrolled keys change). Re-enroll the PCR 7 keyslot too. See [TPM and LUKS](../tpm-luks/).

`rotate-keys` is destructive in the sense that any out-of-band copy of the old keys becomes useless for boot. It is non-destructive to data: nothing in `/var` or `/home` is touched.

## Verification

After any operation, verify:

```
sudo cache22-secureboot status
sudo bootctl status                # Detailed sd-boot view.
sudo sbctl status                  # sbctl's view of enrolled keys.
```

`bootctl` and `sbctl` give finer-grained info if `cache22-secureboot status` does not show enough.

## Common workflows

### Initial setup (typically done by cache22-install)

```
sudo cache22-secureboot enable
# Reboot into firmware setup, put firmware in setup mode.
sudo systemctl reboot
# After reboot, sd-boot enrolls keys. Verify:
sudo cache22-secureboot status
```

### Recover after firmware reset cleared cache22 PK

```
# Symptom: cache22 boots but cache22-secureboot status reports SB disabled
# or PK not enrolled. Firmware reset wiped it.
sudo cache22-secureboot enable
sudo systemctl reboot
# In firmware setup, confirm setup mode (PK was cleared).
# After reboot, keys re-enrolled.
```

### Periodic key rotation

```
sudo cache22-secureboot rotate-keys
# Reboot into firmware setup, put firmware in setup mode.
sudo systemctl reboot
# After enrollment:
sudo cache22-encryption remove /dev/<luks-dev>
sudo cache22-encryption enroll /dev/<luks-dev>
# Re-enroll TPM keyslots.
```

### Disable Secure Boot temporarily

If something is wrong with the SB chain and you need to boot without enforcement:

1. Reboot into firmware setup.
2. Disable Secure Boot.
3. Boot. cache22 runs without SB enforcement; UKIs are still loaded but not verified.
4. After fixing the issue:
   ```
   sudo cache22-secureboot enable
   ```
5. Reboot into firmware setup, put firmware in setup mode (or re-enable SB which puts most firmwares in setup mode automatically), and reboot again.

## See also

- [Boot Chain](../boot-chain/) for what these keys protect.
- [TPM and LUKS](../tpm-luks/) for the keyslot re-enrollment after `rotate-keys`.
- [Threat Model](../threat-model/) for the security implications of each operation.
- [First-Boot Secure Boot Setup](../../getting-started/secure-boot-first-boot/) for the firmware setup-mode procedure.
