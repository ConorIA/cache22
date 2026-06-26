# Initramfs

cache22 splits the initramfs into separate img files. The UKI builder
(`/usr/libexec/cache22/resign-uki`) assembles them into one UKI at install and
on every `bootc` upgrade. The kernel unpacks concatenated cpio segments, so
several imgs combine into one initramfs at boot.

## The imgs

### Base img

`/usr/lib/modules/<kver>/initramfs.img`, built by
`scripts/generate-initramfs.sh`. It is the bare minimum needed to find the root
filesystem and unlock LUKS: storage controllers, btrfs/xfs/ext4, device-mapper,
dm-crypt, TPM2, the boot stack (bootc, ostree, composefs, systemd), and basic
input for typing a passphrase.

The base img is always sufficient to boot on its own. Tooling that loads only it
(an older `resign-uki`, or the BIOS/GRUB path, which references a single initrd)
still produces a bootable system.

### Microcode img

`/usr/lib/cache22/microcode.img`, also built by `generate-initramfs.sh`. CPU
microcode is independent of the kernel version, so it is built once and shipped
as its own img. Both Intel and AMD microcode are included; the CPU applies
whichever vendor matches. `resign-uki` loads it first, ahead of the main
initramfs, because the CPU applies microcode before the main initramfs is
unpacked.

Keeping microcode out of the base img (`early_microcode=no`) means a microcode
package bump no longer re-pulls the whole initramfs layer.

### User img (optional)

`/var/lib/cache22/initramfs/user-<kver>.img`, built per machine by
`/usr/libexec/cache22/build-user-initrd` when you configure additions. When
present, `resign-uki` uses it in place of the base img. See
[Customizing](#customizing) below.

### Extra segments (extensibility)

`resign-uki` also globs `/usr/lib/cache22/initramfs.d/*.img` in sorted order and
folds any imgs found there into the UKI, after the base img. The directory is
empty today. It exists so a future image can split high-churn content out of the
base img (for example firmware, or a driver set) into its own img, and therefore
its own OCI layer, by simply shipping a numbered img there. Because resign-uki
globs this directory rather than hardcoding names, the resign-uki already
deployed on a machine picks up such a new img on the next upgrade with no code
change. The microcode and base imgs stay hardcoded: microcode must load first,
and the base img is the kernel-specific anchor ostree manages.

## What is excluded, and why

Out-of-tree and DKMS modules (nvidia, zfs, the Realtek and Intel NIC DKMS
drivers, and so on) are excluded from every img. They are not needed to reach
the root filesystem: the GPU and network come up from the real root via udev
after `switch_root`, and cache22 never uses a ZFS root. They also change on
every driver bump, which would re-pull the initramfs layer. The exclusion is
written dynamically by `generate-initramfs.sh` into
`/usr/lib/dracut/dracut.conf.d/20-cache22-omit-dkms.conf` by enumerating
`updates/` and `extramodules/`, so new DKMS modules are excluded automatically.

The dracut config (`/usr/lib/dracut/dracut.conf.d/10-cache22.conf`) also omits
modules that are not on the boot path for a local btrfs/xfs/ext4 root over
optional LUKS: network-root (iscsi/nfs/cifs), lvm, mdraid, nvdimm, resume,
fido2, pkcs11, hwdb, the VM share/net helpers, and module-signature checking
(enforcement is off). Some of these (lvm, mdraid, resume) may return as their
own imgs if cache22 grows support for them.

## Customizing

To add drivers or other content to your machine's initramfs, for example a NIC
driver and an SSH client so the initramfs can fetch a remote LUKS key:

1. Drop a dracut config file into `/etc/dracut.conf.d/`. It is read on top of
   the image default. Example `/etc/dracut.conf.d/90-remote-unlock.conf`:

   ```
   add_drivers+=" i40e "
   add_dracutmodules+=" network-manager "
   install_items+=" /usr/bin/curl "
   ```

2. Build the user img:

   ```
   sudo /usr/libexec/cache22/build-user-initrd
   ```

3. Apply it (folds the user img into the UKI):

   ```
   sudo systemctl start cache22-resign-uki.service
   ```

   It is also applied automatically on the next `bootc` upgrade or reboot.

Re-run step 2 after a kernel update, since the user img is per kernel version.
If `/etc/dracut.conf.d/` overrides exist but no user img has been built for the
running kernel, `resign-uki` falls back to the base img and prints a warning, so
the machine still boots.

## Limitations

The microcode and user imgs are folded into the UKI, so they apply on UEFI
Secure Boot installs only. The BIOS/GRUB path references a single initrd through
ostree's BLS entry and therefore loads the base img only. This is fine for the
dd/BIOS targets, which are virtual machines (a guest does not apply CPU
microcode; the host does).
