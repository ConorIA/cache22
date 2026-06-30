---
title: Backup and Restore
parent: System Ops
nav_order: 4
---

# cache22-backup

`cache22-backup` has two engines, chosen by the root filesystem. Both write a
single archive stream that can be compressed and encrypted, and both read that
stream back from a file, stdin, or a URL.

`backup` captures the user-adjusted layer of an install and replays it onto a
fresh install of the same image. It does not store what the image already ships,
so the archive is small and stays valid as the base image moves. It works on any
root filesystem. On btrfs it captures each `/var` subvolume efficiently: nested
data subvolumes (for example incus images and VM disks) with `btrfs send`, so
sparse and reflinked data is not expanded into the archive; separately-mounted or
partially-excluded subvolumes (for example `/var/home`) with a dedicated
per-subvolume tar that restores in place. ext4/xfs roots have no subvolumes and
are captured purely as files.

`clone` captures every subvolume of a btrfs root, including the OS itself, using
`btrfs send`. Reflinks, compression, xattrs, nodatacow, and the read-only state
of each subvolume are carried natively, and shared extents (snapshots, container
and VM images) are sent once. A clone is restored onto a fresh disk by the
installer, which partitions, sets up LUKS, receives the subvolumes, rewrites the
disk-bound boot files, and re-signs the boot image with the clone's own key. Use
`clone` for an exact whole-system copy; use `backup` for a small layer that
replays onto any matching install.

Everything is captured at the file and subvolume level. There is no
application-specific handling: container and VM state lives under `/var` and is
captured like any other data.

Scope is the filesystem the root lives on. Anything mounted from a different
filesystem (external disk, USB, NAS, and virtual mounts such as tmpfs or fuse)
is detected by its filesystem UUID and left out, while every subvolume of the
root filesystem is kept.

## Synopsis

```
sudo cache22-backup backup  [options] [-o DIR|-]
sudo cache22-backup clone   [options] [-o DIR|-]
sudo cache22-backup restore [options] [-i FILE|-]
     cache22-backup info    [options] [-i FILE|-]
```

The archive is a single stream (a tar, by default zstd-compressed, optionally
encrypted). With no `-o`, backup and clone write to a tool-owned directory; `-o -`
streams to stdout, so it pipes over ssh. Restore and info read a file, stdin
(`-i -`), or an `http(s)`/`ftp` URL. A clone is not restored with `restore`; it
is restored by the installer (see Restoring a clone).

## Backup options

| Flag | Effect |
| --- | --- |
| `-o, --output DEST` | Where to write. Omit for the default tool-owned directory `/var/lib/cache22/backup/archives` (on the root filesystem, excluded from backups). `-` streams to stdout, for sending the archive off-box. A directory is accepted only if new, empty, or an existing cache22 repo; a non-empty multi-purpose directory is refused, so one is never tagged. Archives are auto-named host + UTC timestamp + level. |
| `--exclude DIR` | Exclude a directory subtree (repeatable). A btrfs subvolume at or under it is dropped entirely, so it is neither sent nor tarred. A subvolume with an exclude *inside* it falls back to a dedicated tar that honors the exclude. |
| `--include DIR` | Re-add a path excluded by default (repeatable). |
| `--full` | Full backup; reset the incremental state. Default when no prior state exists. |
| `--incremental` | Capture only `/var` changes since the last backup. |
| `--no-compress` | Store uncompressed. The default is zstd. |
| `--tmpdir DIR` | Staging directory. Default `/var/tmp`. |
| `--dry-run` | Report what would be captured. Write nothing. |

## Clone options

| Flag | Effect |
| --- | --- |
| `-o, --output DEST` | As for backup. Archives are auto-named `cache22-clone-host-time`. |
| `--exclude DIR` | Drop a subtree or a whole subvolume (repeatable). A subvolume whose path falls under an exclude is not sent; an excluded subtree inside the OS root's `/var` is removed from the sent copy. |
| `--include DIR` | Re-add a path excluded by default (repeatable). |
| `--no-compress` | Store uncompressed. The default is zstd. |
| `--tmpdir DIR` | Staging directory. It holds the send streams before they are packaged, so for a large system point it at a disk with room for a full copy of the data. |
| `--dry-run` | List the subvolumes that would be sent. Write nothing. |

A clone keeps the per-machine Secure Boot key (`/var/lib/cache22/sbkey`), because
the restore reuses it to re-sign the boot image. A tar backup drops it, because a
tar restore lands on an install that already has its own key.

## Restore options

| Flag | Effect |
| --- | --- |
| `-i, --input FILE` | Read the archive from FILE, stdin (`-`, the default), or a URL. |
| `--force` | Restore even if the archive's image digest differs from the running image. |
| `--dry-run` | Report what would be restored. Change nothing. |

## Encryption

Any command accepts a key source. Encryption uses `openssl enc`
(AES-256-CTR, PBKDF2). An encrypted archive carries the `Salted__` header, so
`info`, `restore`, and the installer detect it and ask for the key.

| Flag | Effect |
| --- | --- |
| `--passphrase` | Prompt for a passphrase. |
| `--passphrase-file FILE` | Read the passphrase from FILE. |
| `--key-file FILE` | Use FILE as a symmetric key. |

## Examples

### Backup (tar overlay, any filesystem)

```
# Full backup to the default location (/var/lib/cache22/backup/archives)
sudo cache22-backup backup

# Backup to a USB drive (a new or empty directory)
sudo cache22-backup backup -o /run/media/usb/cache22-backups

# Incremental backup: only /var changes since the last run
sudo cache22-backup backup --incremental
```

### Clone (whole btrfs filesystem, btrfs only)

```
# Clone to a USB drive, encrypted (prompts for a passphrase)
sudo cache22-backup clone --passphrase -o /run/media/usb/cache22-clones

# Clone leaving large rebuildable container storage out
sudo cache22-backup clone --exclude /var/lib/containers/storage -o /mnt/disk
```

### Over ssh (no archive ever touches local disk)

`-o -` writes the archive to stdout and `-i -` reads it from stdin, so either
engine streams over a pipe. The data is compressed (and, with a key, encrypted)
on the source, so only the compressed stream crosses the network.

```
# PULL a backup to the workstation (tar)
ssh root@host 'cache22-backup backup -o -' > host.c22b

# PULL an encrypted clone to the workstation
ssh root@host 'cache22-backup clone --passphrase-file /root/k -o -' > host.clone.c22b

# PUSH a tar backup from the workstation onto a freshly installed host
ssh root@host 'cache22-backup restore -i -' < host.c22b

# Restore a tar backup straight from an http server
sudo cache22-backup restore -i https://example.com/host.c22b
```

### Inspect and restore locally

```
# Inspect any archive (tar or clone) without restoring
cache22-backup info -i host.c22b

# Restore a tar backup onto a fresh install of the same image
sudo cache22-backup restore -i host.c22b
```

A clone is restored by the installer, not by `restore`; see
[Restoring a clone](#restoring-a-clone) below.

## Incremental backups

`--incremental` (tar engine only) uses a GNU tar snapshot kept in
`/var/lib/cache22/backup`. The first run, or `--full`, writes a level-0 archive
and resets the snapshot. Later `--incremental` runs capture only `/var` files
changed since the previous run. `/etc` is small and is always captured in full.

To restore an incremental chain, restore the full archive first, then each
increment in order; each one applies its `/var` delta, including deletions.

## Restoring a tar backup

A tar restore lands the user layer on a freshly installed cache22 of the same
image. It does not restore disk identity (`fstab`, `crypttab`, `machine-id`) or
TPM enrollment, which the installer owns for the target. After a restore:

1. Re-enroll TPM auto-unlock with `cache22-encryption enroll <luks-device>`.
2. Review enabled services, then reboot.

`restore` refuses to run when the archive's image digest does not match the
running image, unless `--force` is given. Restoring onto a different image
version is best-effort: the `/etc` overlay may collide where the image changed a
default the user also changed.

## Restoring a clone

A clone is restored by the installer, not by `restore`. Boot the installer and
either give the source on the command line or enter it at the first prompt:

```
# From a clone on a mounted USB drive
cache22-install --restore /run/media/usb/cache22-clones/host.clone.c22b \
    --disk /dev/sda --luks

# From an http server
cache22-install --restore https://example.com/host.clone.c22b --disk /dev/sda

# PUSH a clone in over ssh: stream it from the workstation into the installer
# (the target boots the installer environment, reachable over ssh)
cache22-install --restore - --disk /dev/sda < host.clone.c22b   # run on the target
#  e.g. driven from the workstation:
ssh root@installer-env 'cache22-install --restore - --disk /dev/sda' < host.clone.c22b
```

The source can be a file path, an `http(s)`/`ftp` URL, or `-` for stdin (so a
clone can be streamed in over ssh). For an encrypted clone, add the matching
`--restore-passphrase`, `--restore-passphrase-file FILE`, or
`--restore-key-file FILE`. The installer:

1. Partitions the disk and, with `--luks`, sets up a fresh LUKS volume with a new
   passphrase. Partition sizes and UUIDs do not need to match the source.
2. Creates a fresh btrfs and receives every subvolume from the clone, including
   the OS root, at its original path with its original read-only state.
3. Rewrites only the disk-bound boot files for the new disk: `fstab`, `crypttab`,
   the kernel command line, and the `root=` UUID in the boot entries.
4. Re-signs the boot image with the clone's own Secure Boot key, which rode in
   with the root subvolume, so the restored system boots under the same key.

The account, hostname, locale, timezone, services, and data all come from the
clone. Because the LUKS header is new, re-enroll TPM auto-unlock after first boot
with `cache22-encryption enroll <luks-device>`. The disk must be at least as
large as the data in the clone.

## Configuration

`/etc/cache22/backup.conf` is sourced if present. It may add to the default
exclude set:

```
EXTRA_EXCLUDE=(/var/lib/some-large-cache /var/games)
```

The default exclude set is intentionally minimal. For a tar backup it drops
ephemeral data (`/var/cache`, `/var/tmp`), this tool's own archive directory, and
machine-bound boot and security state (`machine-id`, `fstab`, `crypttab`, and the
Secure Boot key). A clone keeps the Secure Boot key but otherwise drops the same
ephemeral and self-referential paths. Everything else, including containers and
their images and VM disks, is captured. To leave large rebuildable container or
VM storage out of a backup, add it with `--exclude` or `EXTRA_EXCLUDE`, for
example `/var/lib/containers/storage`.

## Where archives go, and why backups never capture backups

By default archives are written to the tool-owned directory
`/var/lib/cache22/backup/archives`, which is already excluded. A directory given
with `-o` is accepted only when it is new, empty, or already a cache22 backup
repo; a non-empty multi-purpose directory is refused, so the tool never tags one
by mistake. Any directory it does write into is marked with a standard
`CACHEDIR.TAG` and skipped by later backups (and by any tool honoring the tag),
and the current output file is excluded explicitly. Archives placed somewhere by
other means (copied in by hand) are not tagged; keep those off the backed-up
filesystem or add their directory to `EXTRA_EXCLUDE`.
