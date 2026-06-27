#!/usr/bin/env bash
# cache22-common.sh — shared constants for the cache22 installer tools.
# Sourced by cache22-install and cache22-repair, and shipped beside them
# (build-iso.sh installs all three into /usr/local/bin). Anything injected
# into another environment to run cache22-install (e.g. a kexec restore)
# must carry this file too.

# btrfs mount options for the root and home subvolumes. compress=zstd:1 is the
# cheap-good compression Fedora atomic uses; noatime + space_cache=v2 +
# discard=async are SSD-friendly defaults. A restore reuses these so a restored
# system mounts exactly like a fresh install.
BTRFS_OPTS="compress=zstd:1,noatime,space_cache=v2,discard=async"
