---
title: cache22-reboot
parent: Updates and Reboots
nav_order: 3
---

# cache22-reboot

`cache22-reboot` applies a staged update. It does a full reboot by default, or an opt-in kexec, based on `/etc/cache22/reboot.conf` and the command-line flags. See [Two Reboot Paths](../two-reboot-paths/) for the strategy details.

## Synopsis

```
sudo cache22-reboot [--kexec] [--kexec-force] [--hard] [--check] [--no-fallback]
```

| Flag | Effect |
| --- | --- |
| (none) | Full reboot, or kexec when `KERNEL_CHANGE_STRATEGY=kexec` is set. |
| `--kexec` | Prefer kexec. Falls back to a full reboot if LUKS would need a passphrase, unless `--no-fallback`. |
| `--kexec-force` | kexec even if LUKS will need a passphrase prompt. |
| `--hard` | Force full reboot regardless of state. |
| `--check` | Print the strategy that would run. Do not reboot. |
| `--no-fallback` | Abort instead of falling back to a full reboot if the chosen strategy fails. |

## Configuration

`/etc/cache22/reboot.conf`:

```
KERNEL_CHANGE_STRATEGY=hard  # hard (default), kexec, or kexec-force
```

`KERNEL_CHANGE_STRATEGY=kexec` switches the default from full reboot to kexec. `kexec-force` also kexecs when LUKS will need a passphrase prompt.

CLI flags override the config for that invocation.

## Examples

### Preview the strategy

```
$ sudo cache22-reboot --check
strategy: hard - hard reboot (set KERNEL_CHANGE_STRATEGY=kexec or pass --kexec for kexec)
  staged digest:        sha256:f00e2552043fef13...
  KERNEL_CHANGE_STRATEGY: hard
```

Or when nothing is staged:

```
$ sudo cache22-reboot --check
strategy: hard - hard reboot (nothing staged; rebooting current)
  staged:               (none)
  KERNEL_CHANGE_STRATEGY: hard
```

### Default apply

```
sudo cache22-reboot
```

Does a full reboot into the staged deploy. With `KERNEL_CHANGE_STRATEGY=kexec` set (or `--kexec` passed), it kexecs instead, skipping firmware POST.

### Force a specific path

```
sudo cache22-reboot --kexec     # kexec. Falls back to hard reboot if kexec staging fails.
sudo cache22-reboot --hard      # Full reboot. Always works.
```

### No silent fallback

```
sudo cache22-reboot --kexec --no-fallback
```

If kexec fails (for example, the kernel cannot be loaded), the command exits with an error instead of falling through to a full reboot. Useful when scripting where the fallback would be undesirable.

### Combined with `cache22-update`

```
sudo cache22-update --reboot
```

`cache22-update --reboot` execs `cache22-reboot` after staging. Same auto-pick behavior.

### Apply a previously-staged update

After running `bootc upgrade` directly (without the cache22-update wrapper):

```
sudo cache22-reboot
```

cache22-reboot works the same regardless of who staged the deploy.

## Which path runs

| `bootc status .status.staged` | `KERNEL_CHANGE_STRATEGY` | Selected |
|---|---|---|
| null | any | Full reboot (of current) |
| not null | `hard` (default) | **Full reboot** |
| not null | `kexec` | **kexec** |

## Failure handling

If the chosen strategy fails before triggering the reboot itself (for example, kexec load returns an error), `cache22-reboot` prints an error message and falls back to a full reboot, unless `--no-fallback` is passed.

If the reboot itself fails (rare), the system stays running. Re-run `cache22-reboot`.

If the system fails to come up after a reboot, cache22's health check service auto-rolls back after 3 consecutive failed boots. See [Health Checks](../../system-ops/healthcheck/).

## What runs during a reboot

The shutdown sequence triggers two cache22 hooks via drop-ins on systemd units:

1. `ostree-finalize-staged.service`'s `ExecStop` runs `ostree admin finalize-staged`, writing the BLS entry for the staged deploy.
2. The `50-cache22-uki.conf` drop-in's `ExecStop` runs `/usr/libexec/cache22/resign-uki`, which builds and signs the per-deploy UKI for any newly-finalized deploys.

This happens for both reboot paths (full reboot and kexec).

See [Update Flow](../../architecture/update-flow/) for the full shutdown sequence.

## See also

- [Two Reboot Paths](../two-reboot-paths/). Detail on each reboot strategy.
- [`cache22-update`](../cache22-update/). Staging an update before applying.
- [TPM and LUKS](../../boot-and-security/tpm-luks/). LUKS auto-unlock options for the kexec path.
- [Troubleshooting](../../troubleshooting/) for what to check if a reboot does not produce the expected state.
