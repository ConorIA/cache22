# Secure Boot

cache22 uses the **shim + MOK** chain. Firmware verifies a Microsoft-signed shim, which verifies a Fedora-signed grub2, which uses shim's `shim_lock` verifier to check the cache22-signed kernel against the cache22 cert enrolled into MOK at install time.

## Boot chain

```
UEFI db (Microsoft keys, factory-shipped)
    └─ /boot/efi/EFI/BOOT/BOOTX64.EFI        (Fedora's MS-signed shim — removable-media fallback)
    └─ /boot/efi/EFI/cache22/shimx64.efi     (Fedora's MS-signed shim — primary, efibootmgr entry)
        └─ /boot/efi/EFI/cache22/grubx64.efi (Fedora's signed grub2, Fedora CA in shim's vendor_cert)
            └─ /boot/grub2/grub.cfg           (bootupd's static config; sources grub.cfg.d/*.cfg, runs blscfg)
                └─ /boot/loader/entries/*.conf (BLS Type-1; bootc updates these on every upgrade)
                    └─ /boot/ostree/<deploy>/vmlinuz + initramfs
                        └─ shim_lock_verifier asks shim
                            └─ shim checks kernel against MOK
                               (cache22 cert, enrolled at install)
```

Everything past the kernel handoff (initramfs, kernel modules) loads without further signature checks. If you can write to `/boot`, signature checking is already irrelevant.

## Why Fedora binaries

Fedora's `shim-x64` is Microsoft-signed and accepted by every OEM's factory `db`. Fedora's `grub2-efi-x64` is signed by the Fedora SB CA inside shim's `.vendor_cert` PE section, so shim trusts it automatically. The chain MS → shim → grub works on any UEFI system without MOK enrollment for grub — only the kernel needs MOK.

The Containerfile pulls current Fedora binaries via `FROM registry.fedoraproject.org/fedora:latest` in a multi-stage build. Bootupd manages ESP updates automatically when new images are deployed.

## What gets signed at build time

`scripts/sign-secureboot.sh` plain-`sbsign`s every kernel at `/usr/lib/modules/*/vmlinuz` with the cache22 SB key. No `objcopy`, no SBAT injection — the bzImage's dual-format PE is preserved as-is. Per shim's SBAT spec, SBAT applies to chainloaded EFI binaries (shim, grub), not kernels.

The cache22 SB private key is mounted via buildah `--mount=type=secret`, scoped to the signing RUN step only — never persisted to a layer. Fork-PR builds without secret access ship unsigned kernels (boot fine with SB off; fail shim verification with SB on, by design).

## Install-time wiring

`bootupctl install` (invoked by `bootc install --bootloader=grub`) handles the ESP:

- `/EFI/cache22/shimx64.efi` — Fedora's MS-signed shim (primary boot entry)
- `/EFI/cache22/grubx64.efi` — Fedora's signed grub2
- `/EFI/BOOT/BOOTX64.EFI` — removable-media fallback (same shim)
- `/boot/grub2/grub.cfg` + `/boot/grub2/grubenv` — static grub config written by bootupd
- `/boot/grub2/bootuuid.cfg` — partition UUID wiring
- efibootmgr registration pointing at `/EFI/cache22/shimx64.efi`

The installer then adds cache22-specific extras:

- `/EFI/BOOT/sbcert.der` — cache22 cert in DER form (manual MokManager fallback: "Enroll key from disk")
- `/EFI/BOOT/mmx64.efi` — MokManager copy at the removable-media path; required when firmware falls back to `/EFI/BOOT/BOOTX64.EFI` and shim looks for mmx64 alongside itself
- `/boot/boot → .` self-symlink — BLS entry path resolution
- `efibootmgr --create` belt-and-braces entry for `/EFI/cache22/shimx64.efi` (only if bootupd didn't register one)

`queue_mok_enrollment()` runs `mokutil --import` with password `cache22sb`. This writes `MokListNew` in NVRAM; shim picks it up on the next boot.

## First boot UX

1. Firmware loads shimx64.efi (MS-signed, accepted via db).
2. shim sees `MokListNew` non-empty → launches MokManager (blue screen).
3. Pick "Enroll MOK" → "Continue" → "Yes" → type `cache22sb`.
4. MokManager writes the cert into `MokListRT` and reboots.
5. Firmware → shim → grub → kernel. shim now trusts cache22 via MOK; the cache22-signed kernel passes verification.

Subsequent boots skip MokManager — the cert stays in `MokListRT` until explicitly removed.

If the password flow fails, pick "Enroll key from disk" and select `/EFI/BOOT/sbcert.der`.

## After install: cache22-secureboot

```
cache22-secureboot status      # SB state, MOK enrollment, kernel sig
cache22-secureboot enroll      # queue MOK enrollment + set BootNext to MokManager
cache22-secureboot unenroll    # queue MOK removal
```

Most users never need this — the installer handles enrollment.

## Bootloader updates

`bootloader-update.service` (from the `bootupd` package) runs `bootupctl update` on every boot. It's idempotent — a no-op when the ESP already matches `/usr/lib/efi/` in the running image. When `bootc upgrade` delivers a new image with updated Fedora bootloader binaries, the next reboot refreshes the ESP automatically.

## Threat model and known limitations

**What SB protects against:** a modified bootloader or kernel image on disk cannot be loaded — the MS-signed shim won't load an unsigned grub; shim won't load a kernel whose signature isn't in MOK or a trusted vendor cert.

**What SB does NOT protect (same gap as Bazzite, default Fedora, default Ubuntu):**

The initramfs lives unsigned on `/boot` (ext4) and is loaded by grub directly with no signature semantics. An attacker with offline write access to `/boot` can replace `initramfs.img` with one that logs the LUKS passphrase, bypasses unlock, or persists a rootkit before pivoting to the encrypted root.

**Mitigation:** TPM2 PCR-bound LUKS unlock via `cache22-encryption`. PCR 0 (firmware) and PCR 7 (Secure Boot state) are bound to the LUKS unlock key. Any tampering with those measurements causes the TPM to refuse key release — the user gets a passphrase prompt instead of auto-unlock, surfacing that something changed. This is detection, not prevention.

For environments where offline `/boot` access is a real threat, encrypting `/boot` itself (LUKS + grub's `cryptodisk` module) is the practical extra step. The installer's `--luks` path currently encrypts root only.
