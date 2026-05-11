---
title: Pinning and Rollback
parent: Updates and Reboots
nav_order: 6
---

# Pinning and Rollback

cache22 supports pinning to specific image builds and rolling back to the previous deployment.

## Image tags

Every successful build pushes three tags per variant:

| Tag | Mutability | Use case |
|---|---|---|
| `:rolling` | Moves with each build. | Default. What `cache22-update` follows. |
| `:YYYY-MM-DD` | Latest build of that day. | Pin to a known-good day. |
| `:sha-<7chars>` | Immutable per-commit pointer. | Pin to an exact commit. |

Available tags are listed at `https://github.com/cmspam/cache22/pkgs/container/cache22-<variant>` (substitute your variant name).

## Pinning to a specific build

If a fresh upgrade breaks something, pin to a known-good day or commit. Use `cache22-rebase`:

```
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:2026-05-04
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:sha-9065ce1
```

After pinning, `cache22-update` follows the pinned reference, not `:rolling`. To return to the rolling stream:

```
sudo cache22-rebase --variant cachy-kde   # Or whichever variant is in use.
```

The `--variant` form re-points to `:rolling` for the named variant.

`cache22-rebase` is documented in detail at [Variant Switching](../../system-ops/rebase/).

## Rollback after a bad upgrade

Three rollback mechanisms are available.

### Roll back the staged deploy before rebooting

If an update is staged but not yet applied, dropping the staged deploy reverts to the booted image:

```
sudo bootc rollback
```

Wait, this is wrong terminology. `bootc rollback` flips the booted and rollback deploys; it does not drop the staged deploy. To drop a staged deploy without applying it:

```
sudo bootc upgrade --check    # Confirm staged is what you expect.
# There is no direct "cancel staged" subcommand.
# The staged deploy will be overwritten by the next bootc upgrade
# or replaced by `bootc switch` to another image.
```

To force-replace the staged with whatever the booted image's current digest is:

```
DIGEST=$(sudo bootc status --json | jq -r .status.booted.image.imageDigest)
sudo bootc switch --transport registry "ghcr.io/cmspam/cache22-<variant>@$DIGEST"
```

This stages the booted image's exact content. A subsequent reboot is then a no-op pivot.

### Roll back after rebooting into a bad deploy

```
sudo bootc rollback
sudo cache22-reboot     # Or sudo systemctl reboot.
```

`bootc rollback` flips the booted and rollback deploys. The next reboot lands on the previous deploy.

### Auto-rollback after failed boots

If a deploy boots but fails health checks 2 minutes after boot, `cache22-healthcheck` increments a counter. After 3 consecutive failed boots, it calls `bootc rollback && systemctl reboot` to revert.

To extend health checks with custom checks, drop scripts into `/etc/cache22/healthcheck.d/required.d/`. See [Health Checks](../../system-ops/healthcheck/).

## Identifying the rollback deploy

```
sudo ostree admin status
```

Output shows the deploys:

```
* default 8c8563ff...3
    origin: <unknown origin type>
  default 2a6c8f3e...0 (rollback)
    origin: <unknown origin type>
```

The `*` marks the booted deploy. `(rollback)` marks the deploy that `bootc rollback` would flip to.

To see the image refs for each:

```
sudo bootc status
```

Look at `.status.booted.image.image` and `.status.rollback.image.image`.

## What survives a rollback

A rollback flips which deploy is "current". The other deploy stays on disk. User data in `/var` and `/home` is per-stateroot (same content visible from either deploy). Configuration in `/etc` has the version from the now-active deploy (post-merge from when that deploy was first booted).

What does NOT survive rollback:

- Changes to `/usr` made with `bootc usroverlay` since they live in a tmpfs and are discarded on reboot regardless.
- Files added to the booted deploy's `/etc` since the deploy was first booted, if those files conflict with a different version in the rollback deploy's `/etc`. Per-file merge semantics apply.

## Common workflows

### Pin to yesterday's build, then update tomorrow

```
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:2026-05-09
sudo cache22-reboot
# Confirmed working. To follow rolling again:
sudo cache22-rebase --variant cachy-kde
sudo cache22-reboot
```

### After a bad upgrade

```
# System booted, but something is broken.
sudo bootc rollback
sudo cache22-reboot     # Reverts.
# Investigate while running the previous deploy.
```

### Cancel a staged update before applying

```
# An update was staged but the changelog shows something we do not want.
DIGEST=$(sudo bootc status --json | jq -r .status.booted.image.imageDigest)
sudo bootc switch --transport registry "ghcr.io/cmspam/cache22-cachy-server@$DIGEST"
# Now staged matches booted. cache22-reboot will be a no-op pivot.
```

## See also

- [`cache22-update`](../cache22-update/) for the standard fetch + stage flow.
- [Variant Switching](../../system-ops/rebase/) for switching between variants.
- [Health Checks](../../system-ops/healthcheck/) for auto-rollback details.
