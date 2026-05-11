---
title: Threat Model
parent: Boot and Security
nav_order: 4
---

# Threat Model

This page enumerates what cache22's Secure Boot + TPM2 LUKS configuration protects against and what it does not.

## What is protected

### Cmdline tampering at the loader

The kernel command line is part of the signed UKI's `.cmdline` PE section. Modifying it invalidates the signature; the firmware refuses to load the UKI.

sd-boot's editor is disabled (`editor no` in `loader.conf`). sd-stub ignores any external cmdline override under SB enforcement.

### Substituting an unsigned kernel or UKI

Any binary loaded via `LoadImage()` is verified by firmware against the enrolled DB. Unsigned binaries are rejected. cache22 enrolls only its own per-machine db key plus Microsoft DB keys; binaries signed by other keys are rejected.

### Disk theft

The root filesystem is LUKS-encrypted in the recommended install. The SB signing key, TPM PCR-policy key, and per-machine kargs all live on the encrypted root. An attacker with only the disk cannot read these.

The TPM is per-device. The encrypted LUKS keyslot is sealed to the TPM2 chip in the user's machine. Moving the disk to another machine does not give that machine's TPM the ability to unseal.

### Substituted UKI on the unencrypted ESP

The ESP is unencrypted (FAT32). UKIs are visible on the ESP. An attacker can copy them, examine them, or replace them. However:

- Replacing with an unsigned UKI: firmware rejects it under SB.
- Replacing with a Microsoft-signed binary (e.g., a different Linux distro's shim): different binary boots, but PCR 7 changes (different verification chain) and TPM unseal fails for both PCR 11 and PCR 7 keyslots.
- Replacing with a self-signed UKI: requires the attacker's key to be in firmware DB. cache22's enrolled db is per-machine and lives only on the encrypted root, so attacker cannot easily add a key.

### Firmware key substitution by an unauthorized party

cache22 enrolls its own PK as the firmware Platform Key. Subsequent modifications to KEK or db require the PK holder's signature. An attacker with brief physical access cannot replace the cache22 db with their own without first replacing the PK, which requires putting the firmware back in setup mode (typically requires either the firmware setup password or physical access to clear it via a board jumper).

### Firmware update replacing sd-boot

`systemd-boot-update.service` is masked. `cache22-resign-uki` re-signs and reinstalls sd-boot when the in-image binary is newer than the on-ESP copy, using the per-machine SB key. systemd's normal upstream sd-boot replacement (which would copy the unsigned upstream binary over our locally-signed copy) cannot run.

### Per-deploy boot path integrity (with PCR 11 keyslot only)

When LUKS is bound to PCR 11 only (no PCR 7 fallback), a Type 1 BLS-entry attack is blocked. An attacker with the db key + ESP write access who plants a `/loader/entries/x.conf` referencing a separately-signed kernel cannot get LUKS auto-unlocked. PCR 11 won't reach any signed prediction since sd-stub does not run for non-UKI boot paths.

This protection is lost when a PCR 7 fallback keyslot is also enrolled. See [TPM and LUKS](../tpm-luks/) for the tradeoff.

## What is NOT protected

### Whole-machine theft

If the attacker has the entire physical machine (disk, TPM, firmware), they can power it on. The signed UKI on the ESP loads, sd-stub measures PCR 11 to the legit value, the TPM unseals LUKS, and the attacker has full access.

This is a fundamental limitation of TPM-only LUKS without a user-typed factor. It applies to any TPM auto-unlock setup, not specifically to cache22.

To defend against whole-machine theft:

- Add a user-typed factor (passphrase, FIDO2 key) instead of or in addition to TPM unlock. cache22-encryption only adds TPM unlock; manual `systemd-cryptenroll --recovery-key` or `--fido2-device` adds other factors.
- Set a firmware setup password to prevent BIOS-level changes.
- Use a TPM that is glued or soldered to the board (most are) so removal is destructive.

### A userspace-root attacker installing persistence

An attacker with root userspace access has access to the SB signing key (`db.key`) and the TPM PCR-policy key (`tpm-pcr11.key`). Both live on the encrypted root which is, by definition, unlocked while the system is running.

The attacker can:

1. Sign a malicious UKI with `db.key`. Place it on the ESP.
2. Sign a `.pcrsig` for that UKI's measurements with `tpm-pcr11.key`. Embed in the UKI.
3. Reboot. The malicious UKI loads, PCR 11 reaches its predicted value, TPM unseals LUKS, malicious code has full access.

PCR 11 binding does not defend against this because the keys are co-located on the encrypted root. To defend: the SB and TPM signing keys would need to live elsewhere (HSM, separate machine, smartcard). cache22 does not currently support that.

### Attacker with both `db.key` and `tpm-pcr11.key`

Same as above. Once both keys are exfiltrated, the attacker can produce any boot artifact that satisfies both PCR 11 and PCR 7 binding.

If the attacker has only `db.key` (e.g., from an incomplete backup), PCR 11 binding still defends against the Type 1 BLS-entry attack (they cannot generate a `.pcrsig` that the TPM would accept). PCR 7 binding does not.

### Attackers with firmware setup access

If an attacker has BIOS setup access (no firmware password set), they can:

- Disable Secure Boot. cache22 still boots, but UKIs are not verified.
- Reset Platform Key. Firmware enters setup mode. On next boot, cache22 re-enrolls (the auto-enroll files are still there). The attacker did not gain key access but caused a one-cycle disruption.
- Enroll their own keys before booting cache22. Their keys join the db. They can now boot self-signed binaries.

In all three cases, PCR 7 changes. TPM auto-unlock fails for any keyslot bound to PCR 7. The user is prompted for the LUKS passphrase, surfacing the tampering.

A firmware setup password closes this attack vector. Most modern firmware supports it.

### Software supply chain compromise

If the GitHub Actions build pipeline is compromised, malicious code could land in a published `:rolling` image. Users running `cache22-update` would pull and stage it. On reboot, the malicious deploy runs.

cache22 does not verify image provenance beyond what container registries provide. There is no out-of-band attestation. To defend:

- Pin to specific `:sha-<hash>` tags after manual review (see [Pinning and Rollback](../../updates-and-reboots/pinning-and-rollback/)).
- Build your own fork from audited source (see [Forking](../../building-and-forking/forking/)).

### Rollback to an old vulnerable UKI

An attacker who can write to the ESP can plant an old cache22 UKI (signed by the same per-machine key, since the user's key is unchanged). On reboot, that old UKI loads. PCR 11 reaches the old UKI's predicted value (its `.pcrsig` is still valid, since the TPM key is unchanged). TPM unseals LUKS. Old UKI runs, possibly with a known kernel vulnerability.

cache22 does not implement boot counting or rollback prevention via PCR or NVRAM monotonic counter. The signed-policy approach trades rollback protection for the convenience of not needing re-enrollment after every UKI rebuild.

To defend: regularly delete old UKIs from the ESP (not currently automated; manual `rm /efi/EFI/Linux/cache22-<old-csum>.efi` after confirming the corresponding deploy is no longer in `ostree admin status`).

## Threat model summary

cache22 is designed for the threat profile of a personal device or home server where:

- The user controls physical access most of the time.
- The primary risks are remote network compromise (where SB and TPM unlock are not the relevant defenses) and casual disk theft.
- The user is willing to accept that "root in userspace" is a full compromise (standard Linux security model).

cache22 is NOT designed for:

- High-value devices in adversarial environments without user-typed unlock factors.
- Configurations where signing keys must be held in HSMs or off-machine.
- Defense against well-resourced attackers with the time and equipment to extract TPM keys (TPM2 is generally robust but not unbreakable).

For higher-assurance configurations, look at solutions like systemd-pcrlock with off-machine signing, or TPM-protected secrets in NVRAM with explicit attestation chains.
