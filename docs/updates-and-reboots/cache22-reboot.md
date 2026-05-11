---
title: cache22-reboot
parent: Updates and Reboots
nav_order: 3
---

# cache22-reboot

`cache22-reboot` applies a staged update. It auto-selects between soft-reboot, kexec, and full reboot based on bootc state and `/etc/cache22/reboot.conf`. See [Three Reboot Paths](../three-reboot-paths/) for the strategy details.

## Synopsis

```
sudo cache22-reboot [--soft] [--kexec] [--hard] [--check] [--no-fallback]
```

| Flag | Effect |
| --- | --- |
| (none) | Auto-pick: soft if `softRebootCapable=true`, else kexec or hard per config. |
| `--soft` | Force soft-reboot. Errors if not capable, unless `--no-fallback` is omitted. |
| `--kexec` | Prefer kexec when the kernel changed. |
| `--hard` | Force full reboot regardless of state. |
| `--check` | Print the strategy that would run. Do not reboot. |
| `--no-fallback` | Abort instead of falling back to a full reboot if the chosen strategy fails. |

## Configuration

`/etc/cache22/reboot.conf`:

```
SOFT_REBOOT=auto             # auto (default) or never
KERNEL_CHANGE_STRATEGY=hard  # hard (default) or kexec
```

`SOFT_REBOOT=never` opts out of soft-reboot for the system. Useful if the user does not trust the soft-reboot path.

`KERNEL_CHANGE_STRATEGY=kexec` switches the default for kernel-changing updates from full reboot to kexec.

CLI flags override the config for that invocation.

## Examples

### Preview the strategy

```
$ sudo cache22-reboot --check
strategy: soft - soft-reboot (kernel unchanged, fastest)
  staged digest:        sha256:f00e2552043fef13...
  softRebootCapable:    true
  KERNEL_CHANGE_STRATEGY: hard
  SOFT_REBOOT:            auto
```

Or when nothing is staged:

```
$ sudo cache22-reboot --check
strategy: hard - hard reboot (nothing staged; rebooting current)
  staged:               (none)
  KERNEL_CHANGE_STRATEGY: hard
  SOFT_REBOOT:            auto
```

### Auto-pick (recommended default)

```
sudo cache22-reboot
```

Selects the fastest viable strategy. Same kernel: soft-reboot (~5 sec). Kernel changed with default config: full reboot. Kernel changed with `KERNEL_CHANGE_STRATEGY=kexec`: kexec.

### Force a specific path

```
sudo cache22-reboot --soft      # Soft-reboot, fail loudly if not capable.
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

## When auto-pick selects each path

| `bootc status .status.staged` | `softRebootCapable` | `SOFT_REBOOT` | `KERNEL_CHANGE_STRATEGY` | Selected |
|---|---|---|---|---|
| null | n/a | any | any | Full reboot (of current) |
| not null | `true` | `auto` | any | **Soft-reboot** |
| not null | `true` | `never` | `hard` | Full reboot |
| not null | `true` | `never` | `kexec` | kexec |
| not null | `false` | any | `hard` | Full reboot |
| not null | `false` | any | `kexec` | kexec |

## Failure handling

If the chosen strategy fails before triggering the reboot itself (for example, kexec load returns an error), `cache22-reboot` prints an error message and falls back to a full reboot, unless `--no-fallback` is passed.

If the reboot itself fails (rare), the system stays running. Re-run `cache22-reboot`.

If the system fails to come up after a reboot, cache22's health check service auto-rolls back after 3 consecutive failed boots. See [Health Checks](../../system-ops/healthcheck/).

## What runs during a reboot

The shutdown sequence triggers two cache22 hooks via drop-ins on systemd units:

1. `ostree-finalize-staged.service`'s `ExecStop` runs `ostree admin finalize-staged`, writing the BLS entry for the staged deploy.
2. The `50-cache22-uki.conf` drop-in's `ExecStop` runs `/usr/libexec/cache22/resign-uki`, which builds and signs the per-deploy UKI for any newly-finalized deploys.

This happens for all reboot paths (full reboot, kexec, soft-reboot). soft-reboot does not call `ostree-finalize-staged` through the same path; instead, `cache22-reboot --soft` calls it explicitly before triggering `systemctl soft-reboot`.

See [Update Flow](../../architecture/update-flow/) for the full shutdown sequence.

## See also

- [Three Reboot Paths](../three-reboot-paths/). Detail on each reboot strategy.
- [`cache22-update`](../cache22-update/). Staging an update before applying.
- [TPM and LUKS](../../boot-and-security/tpm-luks/). LUKS auto-unlock options for the kexec path.
- [Troubleshooting](../../troubleshooting/) for what to check if a reboot does not produce the expected state.
