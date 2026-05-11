---
title: Building and Forking
nav_order: 8
has_children: true
permalink: /building-and-forking/
---

# Building and Forking

cache22 is designed to be forked. The full build pipeline runs in the fork's GitHub Actions and pushes images to the fork's `ghcr.io` namespace. No infrastructure on cache22's end is involved.

This section covers:

1. [Forking](./forking/). The minimal steps to get your own variant building.
2. [Containerfile and Packages](./containerfile-and-packages/). Customizing the build (packages, system files, scripts).
3. [CI Pipeline](./ci-pipeline/). What GitHub Actions does, layer rechunking, image push.
