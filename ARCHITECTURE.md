# cache22 architecture

What the system is and why.

## Why bootc + ghcr.io

The OS is shipped as an OCI container image; `bootc upgrade` deploys image updates atomically with rollback. Distribution via ghcr.io because it is OCI-native, has no anonymous-pull rate limits for public images, and integrates trivially with GitHub Actions.

## Base: `cachyos/cachyos-v3`

Already x86-64-v3 optimized, has CachyOS repos and signing keys configured. We add multilib + custom repos and install everything else on top. Pulled at build time from Docker Hub (build-time pulls are not subject to the "ghcr-only distribution" requirement, which applies to end-user delivery).

## Kernel: `linux-cachyos-bore-lto`

LTO build of CachyOS's default scheduler (BORE). Pre-built per-kernel modules (`-headers`, `-nvidia-open`, `-zfs`, `-r8125`) are available, so we don't need DKMS — DKMS doesn't fit the immutable model because it rebuilds at install time and we don't have an "install time."

## Initramfs: dracut (not mkinitcpio)

bootc's tooling assumes dracut's hook model. mkinitcpio works for stock Arch but doesn't have ostree/composefs hooks. The CachyOS-shipped `cachyos-hooks` package contains an mkinitcpio-tied plymouth-initramfs hook which we delete during build (`scripts/finalize-image.sh`).

## Bootloader: Fedora's pre-signed shim + grub, managed by bootupd

The Containerfile uses a multi-stage build: a `fedora-bootloader` stage installs `shim-x64` and `grub2-efi-x64` from `registry.fedoraproject.org/fedora:latest`, renames `EFI/fedora` → `EFI/cache22`, and copies the result into `/usr/lib/efi/` in the main image. `scripts/generate-bootupd-metadata.sh` then hand-writes `/usr/lib/bootupd/updates/EFI.json` and the payload tree so bootupd can manage ESP updates. (`bootupd generate-update-metadata` cannot be used — it shells out to `rpm -q` for version info, which doesn't work on a pacman-based image.)

At install time, `bootc install --bootloader=grub` invokes `bootupctl install`, which copies shim + grub onto the ESP at `/EFI/cache22/`, writes a removable-media fallback at `/EFI/BOOT/BOOTX64.EFI`, drops static grub configs under `/boot/grub2/`, writes `/boot/grub2/bootuuid.cfg`, and runs `efibootmgr`. The installer (`install_cache22_esp_extras()`) then adds cache22-specific extras: `/EFI/BOOT/sbcert.der`, `/EFI/BOOT/mmx64.efi`, and the `/boot/boot` self-symlink. If no `cache22` efibootmgr entry exists after bootupd runs, the installer calls `efibootmgr --create` as a belt-and-braces fallback.

On every boot, `bootloader-update.service` (from the `bootupd` package) runs `bootupctl update` — idempotent, no-op when the ESP already matches `/usr/lib/efi/`. When a `bootc upgrade` delivers newer Fedora bootloader binaries, the next reboot refreshes the ESP automatically.

`scripts/sign-secureboot.sh` plain-`sbsign`s every kernel in `/usr/lib/modules/*/vmlinuz` with the cache22 SB key. Grub's `shim_lock` verifier asks shim to verify the kernel against the cache22 cert enrolled into MOK at install time. Trust chain ends there: initramfs and kernel modules load without further verification. Threat model: write access to `/boot` is already game over.

Grub (not systemd-boot) because grub bundles its own ext4 driver and reads `/boot` directly — sd-boot only reads FAT, which would require duplicating every kernel onto the ESP. With grub, kernels live in exactly one place (`/boot/ostree/<deploy>/`), managed by ostree/bootc.

## Filesystem layout (the bootcrew pacman trick)

The pacman database, cache, and hooks are moved from `/var/lib/pacman` to `/usr/lib/sysimage/pacman` so they ship inside the image. `/var` is per-machine and discarded between deploys; without this rewrite, fresh installs would have an empty package DB and `pacman -Q` would show nothing.

This is the same pattern Fedora uses for rpmdb at `/usr/share/rpm`.

## Pacman binary: kept

Read operations (`pacman -Q*`, `pacman -Si`, `pacman -F`) are useful and harmless. Write operations fail because `/usr` is read-only; with `bootc usroverlay` they succeed but are ephemeral. Removing the binary to prevent what the filesystem already prevents would be over-engineering.

## Custom pacman repos

Four consumed via repo-priority (placed above `[extra]` in `pacman.conf`):

- `[bootc-v3]` — bootc + bootupd built for x86-64-v3 baseline from [`cmspam/bootc-v3`](https://github.com/cmspam/bootc-v3). The cachyos-v3 default RUSTFLAGS would emit AMD-only SSE4a instructions and SIGILL on Intel; this repo rebuilds with the v3 baseline.
- `[qemu-patched-v3]` — patched QEMU from [`cmspam/qemu-patched`](https://github.com/cmspam/qemu-patched). `pacman -S qemu-desktop` automatically pulls the patched version.
- `[xe-virt-host-v3]` — patched virglrenderer from [`cmspam/xe-virt-repo`](https://github.com/cmspam/xe-virt-repo). `pacman -S virglrenderer` pulls the patched version.
- `[gamescope-patched-v3]` — patched gamescope from [`cmspam/gamescope-patched`](https://github.com/cmspam/gamescope-patched), fixing nvidia steam-remote-play black screen + inverted colors.

`SigLevel = Optional TrustAll` for all (the upstream pipelines use `--skippgpcheck`).

## Secure Boot: shim + MOK (no UEFI db enrollment)

The chain is `firmware (MS in db) → shim (Fedora MS-signed) → grub (Fedora CA in shim's vendor_cert) → kernel (cache22 cert via MOK)`. Microsoft's keys stay in `db` untouched, preserving dual-boot Windows + fwupd + signed third-party drivers.

The installer's `queue_mok_enrollment()` runs `mokutil --import` against the cache22 cert with password `cache22sb`. On first reboot, shim sees `MokListNew` non-empty and launches MokManager; the user types the password to confirm enrollment. The installer also drops the cert at `/EFI/BOOT/sbcert.der` as a fallback for MokManager's "Enroll key from disk" path.

Post-install management is via `cache22-secureboot` (`status` / `enroll` / `unenroll`). We do not enroll into UEFI db, do not generate per-machine sbctl keys, and do not run local re-signers. See [`docs/SECUREBOOT.md`](docs/SECUREBOOT.md).

## TPM2 LUKS unlock: post-install via `cache22-encryption`

Encryption is set up at install time (cryptsetup, LUKS2). TPM2 enrollment is post-install via `cache22-encryption`, binding to PCR 0+7 (firmware + Secure Boot state) so kernel updates don't break unlock.

## Variants: single Containerfile, build-arg driven

Following the [ublue-os/image-template](https://github.com/ublue-os/image-template) and [Bazzite](https://github.com/ublue-os/bazzite) pattern. cache22 currently builds four variants in parallel CI matrix jobs:

- `cachy-kde` / `cachy-server` — built on `cachyos/cachyos-v3` base image, pulling from CachyOS repos. `linux-cachyos-bore-lto` kernel + pre-built per-kernel modules.
- `arch-kde` / `arch-server` — built on `archlinux` base image, pulling from ALHP (x86-64-v3 rebuilds of stock Arch) + stock Arch + chaotic-aur (lowest priority, only consulted for `xone-dkms-git`). ALHP `linux` kernel + DKMS-built modules at image-build time.

The two families are independent at the file level: `packages/cachy-*.txt` + `scripts/inject-custom-repos-cachy.sh` for cachy; `packages/arch-*.txt` + `scripts/inject-custom-repos-arch.sh` for arch. Either family can be removed wholesale without affecting the other.

Adding a new family (e.g. `gnome`):

1. New `packages/<family>-common.txt` + `<family>-kde.txt` + `<family>-server.txt`
2. New `scripts/inject-custom-repos-<family>.sh`
3. Matrix rows in `.github/workflows/build-image.yml` (one per `<family>-<type>`)
4. Entries in `variants.json`

ghcr.io's OCI layer dedup means shared base packages cost storage + pull bandwidth only once across variants.

## Layer rechunking

`scripts/rechunk-cache22.py` post-processes the single-layer build into ~120 per-package layers grouped by alphabetical bucket so `bootc upgrade` redownloads only the layers whose digest changed since the previous rolling tag (typical daily delta: ~100–300 MB instead of multi-GB). It manually constructs the OCI tar, preserves xattrs (security.capability for `newuidmap`/`ping`) via `SCHILY.xattr.*` PAX headers with surrogateescape encoding, and injects empty mount-point dirs that pacman's files DBs omit (`/tmp`, `/sysroot`, `/etc/avahi/services`, etc.). The CI workflow prints an "Upgrade-size delta" summary against the previous rolling tag on every build.

