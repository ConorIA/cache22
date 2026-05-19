---
title: Getting Started
nav_order: 2
has_children: true
permalink: /getting-started/
---

# Getting Started

This section covers installing cache22 and (on UEFI hardware) completing the one-time Secure Boot key enrollment on first boot.

The order to follow is:

1. [Installation](./installation/). Two entry points: hybrid BIOS+UEFI USB installer ISO for bare metal, or a NixOS-based kexec image for VPSes. Both run `cache22-install` after boot. The installer auto-detects firmware mode.
2. [First-Boot Secure Boot Setup](./secure-boot-first-boot/). **UEFI only.** Put firmware in setup mode before the first boot of the installed system so cache22 can enroll its keys. Skip this step on BIOS installs.
3. [Variants](./variants/). What each variant ships and how to pick one.

After first boot completes, see [Updates and Reboots](../updates-and-reboots/) for the day-to-day update workflow.
