---
title: Architecture
nav_order: 7
has_children: true
permalink: /architecture/
---

# Architecture

Internals of cache22's bootc + ostree integration, the per-deploy UKI build pipeline, the filesystem layout, and the update sequence.

This section is for users who want to understand how the system works under the hood. Day-to-day operation does not require this material.

Pages in this section:

1. [bootc and ostree](./bootc-and-ostree/). Roles of bootc and ostree in cache22; how they fit together.
2. [Per-Deploy UKI Build](./per-deploy-uki/). The `resign-uki` script, drop-in triggers, and signing chain.
3. [Filesystem Layout](./filesystem-layout/). Per-stateroot `/var`, `/etc` bind, `/usr/local`, ESP layout.
4. [Update Flow](./update-flow/). The full shutdown sequence: finalize, UKI build, reboot.
