---
title: Updates and Reboots
nav_order: 3
has_children: true
permalink: /updates-and-reboots/
---

# Updates and Reboots

cache22 follows the bootc atomic-update model: a new OS image is staged in a separate slot, and the next reboot applies it. Rollback returns to the previous slot.

The main commands:

| Command | Purpose |
| --- | --- |
| [`cache22-update`](./cache22-update/) | Fetch and stage the next image. |
| [`cache22-reboot`](./cache22-reboot/) | Apply the staged image. Auto-selects from three reboot paths. |
| [`cache22-changelog`](./changelog/) | Show the package-level diff between booted and staged. |
| [`cache22-autoupdate`](./auto-update-and-reboot/) | Schedule unattended `cache22-update` runs. |
| [`cache22-autoreboot`](./auto-update-and-reboot/) | Schedule unattended reboots after auto-updates. |
| [`cache22-rebase`](../system-ops/rebase/) | Switch between cache22 variants or pin to specific images. |

Pages in this section:

1. [Three Reboot Paths](./three-reboot-paths/). How cache22-reboot picks between soft-reboot, kexec, and full reboot.
2. [cache22-update](./cache22-update/). Fetching and staging updates.
3. [cache22-reboot](./cache22-reboot/). Applying staged updates with the right strategy.
4. [Auto-Update and Auto-Reboot](./auto-update-and-reboot/). Hands-off daily updates.
5. [cache22-changelog](./changelog/). Inspecting a staged update before applying it.
6. [Pinning and Rollback](./pinning-and-rollback/). Sticking to a specific build, reverting on failure.
