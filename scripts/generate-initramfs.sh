#!/usr/bin/env bash
# Build dracut initramfs for every installed kernel. dracut (not
# mkinitcpio) because bootc/composefs/ostree's dracut hooks are what
# we rely on. patch-ostree-dracut.sh runs first so the bootc module
# actually installs.

set -euo pipefail

echo "==> Generating dracut initramfs for installed kernels"

SDE="${SOURCE_DATE_EPOCH:-0}"
shopt -s nullglob
for kver_dir in /usr/lib/modules/*/; do
    kver="$(basename "${kver_dir}")"
    if [[ ! -f "${kver_dir}vmlinuz" ]]; then
        echo "    skipping ${kver} (no vmlinuz)"
        continue
    fi
    echo "    building initramfs for ${kver}"
    # Ensure modules.dep is fresh. Pacman's 60-depmod.hook normally
    # handles this, but at least one cachyos kernel bump
    # (linux-cachyos-bore-lto-7.0.5-1) shipped without it firing,
    # leaving dracut to fail with "modules.dep is missing". depmod is
    # idempotent — re-running it when pacman already did is free.
    depmod -a "${kver}"
    # dracut --reproducible runs clamp_mtimes($initdir) which finds all
    # files newer than SOURCE_DATE_EPOCH and touches them down to SDE.
    # With SDE=0 that's every file in initdir. NO faketime wrap here —
    # libfaketime intercepts utimensat, so touch under faketime stores
    # real_mtime - faketime_offset rather than the literal value, which
    # leaves cpio entries with year-2049-ish nonsense. dracut doesn't
    # call any tool that needs faketime (no --uefi, no signing here).
    dracut \
        --force \
        --kver "${kver}" \
        --no-hostonly \
        --reproducible \
        --zstd \
        --quiet \
        "/usr/lib/modules/${kver}/initramfs.img"
done

echo "==> Initramfs generation complete"
