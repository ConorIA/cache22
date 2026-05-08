# cache22 installer

Live ISO + scripted installer that pulls the latest cache22 image from ghcr.io and lays it down with `bootc install to-filesystem`. The ISO is built by `.github/workflows/build-iso.yml` and published as a GitHub Release asset.

## Layout

```
installer/
├── fedora-live/                # Fedora-44 minimal live ISO build
│   └── build-iso.sh            # dnf --installroot + dracut + mksquashfs + xorrisofs
└── cache22-install             # interactive bash TUI; supports --no-prompt scripted mode
```

## Using it

1. Boot the ISO. tty1 auto-logins root; a motd explains how to proceed.
2. Run `cache22-install`. The interactive flow: image variant → disk → optional LUKS → partitioning → user account → hostname → locale → timezone → review.
3. On confirm, the installer:
   - Partitions: ESP (512M FAT32 at `/boot/efi`) + `/boot` (2G ext4, XBOOTLDR) + root + scratch
   - Pulls the image (~8 GB compressed)
   - Runs `bootc install to-filesystem --bootloader=grub`, which invokes `bootupctl install` to copy shim + grub onto the ESP at `/EFI/cache22/`, write the removable-media fallback at `/EFI/BOOT/BOOTX64.EFI`, write `/boot/grub2/` static configs, and register a UEFI boot entry
   - Adds cache22-specific ESP extras: cache22 SB cert at `/EFI/BOOT/sbcert.der`, `mmx64.efi` at `/EFI/BOOT/`, and the `/boot/boot → .` self-symlink
   - Writes user account, hostname, locale, timezone into `<deploy>/etc/`
   - Runs `mokutil --import` to queue MOK enrollment
   - Reclaims the scratch partition back into root (disk scratch mode) or skips (tmpfs scratch mode)
4. First boot: MokManager (blue screen) prompts for the enrollment password (`cache22sb`). After enrollment, shim trusts the cache22-signed kernel and SB boots normally.

## Why Fedora kernel/userland in the live ISO

The ISO needs to boot under Secure Boot on stock OEM hardware. That requires a shim-trusted kernel — one signed by a CA in shim's `vendor_cert`. Fedora's shim ships with the Fedora SB CA there, and Fedora signs its kernel and grub with it. Arch's kernel isn't signed by any CA the firmware or shim trusts out of the box.

The installed system is still Arch/CachyOS — only the live ISO uses Fedora userland.

## Scripted install

```
cache22-install --no-prompt --disk /dev/vda \
    --variant cachy-kde --user testuser --password testpass123 \
    --hostname testhost --locale en_US.UTF-8 --timezone Asia/Tokyo --reboot
```

`--variant cachy-kde|cachy-server|arch-kde|arch-server` is shorthand for `--image ghcr.io/cmspam/cache22-<id>:rolling`. `--image REF` overrides `--variant` if both are passed.

## Building locally

Requires Fedora 44 (or a Fedora 44 container), runs as root:

```bash
sudo dnf install -y dracut squashfs-tools xorriso mtools dosfstools python3
sudo ./fedora-live/build-iso.sh ./out
```

Output: `out/cache22-installer-YYYY.MM.DD.iso`.

## Switching an existing bootc system

From any bootc-based system:

```bash
sudo bootc switch ghcr.io/cmspam/cache22-cachy-kde:rolling
sudo systemctl reboot
```

This keeps the existing bootloader in place. SB will need manual MOK enrollment if the existing chain doesn't already trust the cache22 cert (`sudo cache22-secureboot enroll` after first boot).
