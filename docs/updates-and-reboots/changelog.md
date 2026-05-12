---
title: cache22-changelog
parent: Updates and Reboots
nav_order: 5
---

# cache22-changelog

`cache22-changelog` shows the package-level diff between the booted deployment and any staged update.

## Synopsis

```
cache22-changelog [--check]
```

| Flag | Effect |
| --- | --- |
| (none) | Print the full diff. Requires sudo (reads pacman databases under `/sysroot`). |
| `--check` | Silent. Exit 0 if a staged update exists, 1 if not. Used by login banners. |

## Examples

### Inspect what would change

```
sudo cache22-changelog
```

Example output:

```
==========================================================
  cache22 update pending - reboot to apply

  Booted: ghcr.io/cmspam/cache22-cachy-server:rolling
  Staged: ghcr.io/cmspam/cache22-cachy-server:rolling

  Package changes (37):
    upgraded  linux-cachyos                             7.0.5-1 -> 7.1.0-1
    upgraded  linux-cachyos-headers                     7.0.5-1 -> 7.1.0-1
    upgraded  linux-cachyos-nvidia-open                 7.0.5-1 -> 7.1.0-1
    upgraded  systemd                                   258.4-1 -> 258.5-1
    added     btop                                      1.4.0-1
    removed   nano-syntax-highlighting                  3.5-1

  Reboot:    sudo cache22-reboot     (auto-picks soft-reboot when possible)
  Cancel:    sudo bootc rollback
==========================================================
```

### Silent check (used by login banners)

```
cache22-changelog --check && echo "update pending"
```

Returns exit 0 when a staged deploy exists, 1 otherwise. No output is produced. Used by `/etc/profile.d/cache22-pending-reboot.sh` to decide whether to show the login banner.

## What it shows

For the booted and staged deploys, `cache22-changelog` reads the pacman package database under each deploy's root and produces a three-way diff:

- **added.** Packages present in the staged deploy but not in the booted deploy.
- **removed.** Packages in the booted but removed in the staged.
- **upgraded.** Packages present in both with different versions.

The lists are name-sorted within each category. Counts are shown in the header.

The image references and image timestamps for booted and staged are also included in the output.

## Where the data comes from

cache22 relocates pacman state to `/usr/lib/sysimage/pacman/local/` (instead of `/var/lib/pacman` as on stock Arch). For each deploy, the database lives at:

```
/sysroot/ostree/deploy/<state>/deploy/<csum>.<idx>/usr/lib/sysimage/pacman/local/
```

`cache22-changelog` walks both the booted and staged deploy directories, parses each package's directory name (the standard pacman format `<name>-<version>-<release>`), and emits the diff.

The diff is purely informational. It does not list configuration changes, file additions outside packages, or kernel parameter changes. To see those, compare deploy `/etc` directories or build artifacts manually.

## Common workflows

### Decide whether to apply now or wait

```
sudo cache22-update
sudo cache22-changelog                 # Look at what would change.
sudo cache22-reboot                    # Apply when ready.
# Or:
sudo bootc rollback                    # Cancel (drops the staged deploy).
```

### Inspect before an autoreboot fires

If `cache22-autoreboot` is configured for 04:00 and the user is awake at 22:00 the previous night with a staged update pending:

```
sudo cache22-changelog
```

If the change looks fine, do nothing; the timer will reboot at 04:00. If something looks problematic, `sudo bootc rollback` cancels the staged deploy. (Note: rollback in this context drops the staged deploy. To go back to the previously-booted image after applying an update, run rollback after the reboot, then reboot again.)

### Use in scripts

```
if cache22-changelog --check; then
    echo "Update available, see: sudo cache22-changelog"
fi
```

The silent check is suitable for use in MOTD scripts, shell rc files, or monitoring scripts.

## See also

- [`cache22-update`](../cache22-update/) to fetch and stage an update.
- [`cache22-reboot`](../cache22-reboot/) to apply it.
- [Pinning and Rollback](../pinning-and-rollback/) for cancelling or reverting an update.
