---
title: cache22-update
parent: Updates and Reboots
nav_order: 2
---

# cache22-update

`cache22-update` fetches and stages the next OS image. It does not reboot unless `--reboot` is passed. By default it fetches OS updates only; with `--app-updates` it also runs `flatpak update` and `distrobox upgrade --all`.

## Synopsis

```
sudo cache22-update [--check] [--reboot] [--app-updates] [--if-idle]
```

| Flag | Effect |
| --- | --- |
| (none) | Check for, fetch, and stage the next image. Does not reboot. |
| `--check` | Read-only check. Reports whether an update is available without fetching. |
| `--reboot` | After staging, reboot via `cache22-reboot` (auto-selects strategy). |
| `--app-updates` | Also run `flatpak update -y` and `distrobox upgrade --all`. |
| `--if-idle` | Exit silently if another `cache22-update` is already running. Used by the autoupdate timer to avoid preemption. |

## What it does

The wrapper performs these steps:

1. Run `bootc upgrade --check`. Exit if the registry has no new image (skips redundant re-staging when nothing changed upstream).
2. Run `bootc upgrade`. bootc pulls the new image and stages it as a new ostree deploy.
3. Refresh the pending-reboot MOTD marker (`/run/motd.d/10-cache22-pending-reboot`) so login banners reflect the new state. Trigger a desktop notification on graphical sessions when a new staged deploy appears.
4. If `--app-updates` is passed, run flatpak and distrobox updates as the invoking user.
5. If `--reboot` is passed, exec `cache22-reboot` to apply the staged image.

Finalize of the staged deploy and the per-deploy UKI build do NOT happen here. They run at shutdown when the user reboots. See [Update Flow](../../architecture/update-flow/) for details.

## Examples

### Check for updates without fetching

```
$ sudo cache22-update --check
Update available for ghcr.io/cmspam/cache22-cachy-kde:rolling: sha256:f00e2552...
```

Or if up to date:

```
$ sudo cache22-update --check
No changes in: docker://ghcr.io/cmspam/cache22-cachy-kde:rolling
```

### Fetch and stage, do not reboot

```
sudo cache22-update
```

The new deploy is staged. SSH MOTD and shell login banners will mention the pending update until applied. To inspect what changed: see [`cache22-changelog`](../changelog/).

### Fetch, stage, and reboot

```
sudo cache22-update --reboot
```

This is equivalent to `sudo cache22-update && sudo cache22-reboot`. The reboot uses the same auto-selected strategy as `cache22-reboot` with no flags: soft-reboot if the kernel did not change, otherwise full reboot (or kexec if `KERNEL_CHANGE_STRATEGY=kexec`).

### Also update flatpaks and distroboxes

```
sudo cache22-update --app-updates
```

Runs the OS update first, then flatpak and distrobox updates. The flatpak and distrobox commands are run as the invoking user (from `$SUDO_USER` or `logname`), not as root.

To do both update types and reboot:

```
sudo cache22-update --app-updates --reboot
```

### Skip if another instance is running

```
sudo cache22-update --if-idle
```

Acquires a non-blocking lock on `/var/lock/cache22-update.lock`. If another `cache22-update` (typically the autoupdate timer) holds the lock, exits silently with success. Use this in scripts that should not preempt the timer.

The autoupdate service uses `--if-idle` to avoid running while a manual update is in progress.

## What gets staged

The staged deploy is identified by an ostree commit checksum. To see it:

```
sudo bootc status --json | jq '.status.staged'
```

The deploy directory is created at `/sysroot/ostree/deploy/<stateroot>/deploy/<csum>.<idx>/`. The per-deploy UKI is not yet built; that runs at the next shutdown.

To list all current deploys:

```
sudo ostree admin status
```

Output shows the booted deploy with `*`, the staged deploy with `(staged)`, and the rollback with `(rollback)`.

## When this is a no-op

`cache22-update` exits early in these cases:

- `bootc upgrade --check` reports no changes upstream. The wrapper does not call `bootc upgrade`, avoiding the redundant re-stage that bootc would otherwise do (bootc re-stages the matching image even when there is nothing new).
- `bootc upgrade` runs but reports no new deploy was staged. Rare but possible if the registry race conditions arrange it.

In both cases the marker file is not written and no notification fires.

## Bypassing `cache22-update`

Bare `bootc upgrade` also works:

```
sudo bootc upgrade
```

The shutdown sequence still finalizes and builds the UKI via the `ostree-finalize-staged.service` drop-in. The MOTD marker and desktop notification are also handled through `cache22-pending-motd.service` which is triggered by `bootc-status-updated.target`.

What bare `bootc upgrade` does NOT do:

- The redundant-re-stage avoidance from `bootc upgrade --check`. Bare bootc re-stages even when there is nothing new.
- The `--app-updates` flag (flatpak + distrobox updates).
- The `--if-idle` lock behavior.

For day-to-day use, prefer `cache22-update`.

## See also

- [Three Reboot Paths](../three-reboot-paths/) for what happens when the staged deploy is applied.
- [`cache22-changelog`](../changelog/) to inspect the package-level diff before rebooting.
- [Auto-Update and Auto-Reboot](../auto-update-and-reboot/) for unattended scheduling.
- [Pinning and Rollback](../pinning-and-rollback/) for picking specific builds or reverting after a bad upgrade.
