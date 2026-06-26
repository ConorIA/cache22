---
title: Backup and Restore
parent: System Ops
nav_order: 4
---

# cache22-backup

`cache22-backup` captures the user-adjusted layer of an install and replays it
onto a fresh install of the same image. It does not back up what the image
already ships, so the archive is small and stays valid as the base image moves.

It captures:

| Part | What | How it is found |
| --- | --- | --- |
| `/etc` | files changed or added vs the image default | `ostree admin config-diff` |
| `/var` | everything on the root filesystem, minus an exclude set | tar, optionally incremental |
| subvolumes | the btrfs subvolume layout, recreated on restore | inode-256 scan (skipped on ext4/xfs) |
| Incus | profile, network, and storage definitions; instances on request | `incus ... show` / `incus export` |
| metadata | the image ref and digest, the root filesystem type, the exclude set | `bootc status` |

Scope is the filesystem the root lives on. Anything mounted from a different
filesystem (external disk, USB, NAS, and virtual mounts such as tmpfs or fuse)
is detected by its filesystem UUID and left out, while every subvolume of the
root filesystem is kept.

## Synopsis

```
sudo cache22-backup backup  [options] [-o DIR|-]
sudo cache22-backup restore [options] [-i FILE|-]
     cache22-backup info    [options] [-i FILE|-]
```

The archive is a single stream (a tar, by default zstd-compressed, optionally
encrypted). With no `-o`, backup writes to a tool-owned directory; `-o -` streams
to stdout, so it pipes over ssh. Restore and info read a file or stdin (`-i -`).

## Backup options

| Flag | Effect |
| --- | --- |
| `-o, --output DEST` | Where to write. Omit for the default tool-owned directory `/var/lib/cache22/backup/archives` (on the root filesystem, excluded from backups). `-` streams to stdout, for sending the archive off-box. A directory is accepted only if new, empty, or an existing cache22 repo; a non-empty multi-purpose directory is refused, so one is never tagged. Archives are auto-named host + UTC timestamp + level. |
| `--exclude DIR` | Exclude a directory subtree (repeatable). A btrfs subvolume under it is also dropped from the recreate list, so restore does not recreate an empty subvolume. |
| `--include DIR` | Re-add a path excluded by default (repeatable). |
| `--incus-instances` | Also export Incus instance disks. These can be large. |
| `--no-incus` | Skip Incus. |
| `--full` | Full backup; reset the incremental state. Default when no prior state exists. |
| `--incremental` | Capture only `/var` changes since the last backup. |
| `--no-compress` | Store uncompressed. The default is zstd. |
| `--tmpdir DIR` | Staging directory. Default `/var/tmp`. |
| `--dry-run` | Report what would be captured. Write nothing. |

## Restore options

| Flag | Effect |
| --- | --- |
| `-i, --input FILE` | Read the archive from FILE. `-` is stdin (the default). |
| `--force` | Restore even if the archive's image digest differs from the running image. |
| `--dry-run` | Report what would be restored. Change nothing. |

## Encryption

Either command accepts a key source. Encryption uses `openssl enc`
(AES-256-CTR, PBKDF2). An encrypted archive carries the `Salted__` header, so
`info` and `restore` detect it and ask for the key.

| Flag | Effect |
| --- | --- |
| `--passphrase` | Prompt for a passphrase. |
| `--passphrase-file FILE` | Read the passphrase from FILE. |
| `--key-file FILE` | Use FILE as a symmetric key. |

## Examples

```
# Full backup to the default location (/var/lib/cache22/backup/archives)
sudo cache22-backup backup

# Backup to a USB drive (a new or empty directory)
sudo cache22-backup backup -o /run/media/usb/cache22-backups

# Encrypted backup pulled over ssh to the workstation
ssh root@host 'cache22-backup backup --passphrase-file /root/k -o -' > host.c22b

# Incremental backup (only /var changes since the last run)
sudo cache22-backup backup --incremental

# Inspect an archive without restoring
cache22-backup info -i host.c22b

# Restore onto a fresh install of the same image
sudo cache22-backup restore -i host.c22b
```

## Incremental backups

`--incremental` uses a GNU tar snapshot kept in `/var/lib/cache22/backup`. The
first run, or `--full`, writes a level-0 archive and resets the snapshot. Later
`--incremental` runs capture only `/var` files changed since the previous run.
`/etc` is small and is always captured in full.

To restore an incremental chain, restore the full archive first, then each
increment in order; each one applies its `/var` delta, including deletions.

## Restore notes

A restore lands the user layer on a freshly installed cache22 of the same image.
It does not restore disk identity (`fstab`, `crypttab`, `machine-id`) or TPM
enrollment, which the installer owns for the target. After a restore:

1. Re-enroll TPM auto-unlock with `cache22-encryption enroll <luks-device>`.
2. Review enabled services, then reboot.

`restore` refuses to run when the archive's image digest does not match the
running image, unless `--force` is given. Restoring onto a different image
version is best-effort: the `/etc` overlay may collide where the image changed a
default the user also changed.

## Configuration

`/etc/cache22/backup.conf` is sourced if present. It may add to the default
exclude set or disable Incus:

```
EXTRA_EXCLUDE=(/var/lib/some-large-cache /var/games)
INCUS=no
```

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
