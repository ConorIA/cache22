#!/usr/bin/env bash
# Build dracut initramfs for every installed kernel. dracut (not
# mkinitcpio) because bootc/composefs/ostree's dracut hooks are what we
# rely on. patch-ostree-dracut.sh runs first so the bootc module
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
    # faketime + --reproducible eliminates wall-clock leakage from any
    # dracut module or helper that stamps a build-time into its output.
    faketime "@${SOURCE_DATE_EPOCH:-0}" \
        dracut \
            --force \
            --kver "${kver}" \
            --no-hostonly \
            --reproducible \
            --zstd \
            --quiet \
            "/usr/lib/modules/${kver}/initramfs.img"

    # Post-process the cpio inside initramfs.img to pin every entry's
    # mtime to SDE. dracut --reproducible only resets mtimes for files
    # newer than its tmp initdir; package-installed files (older than
    # initdir) keep their wall-clock mtimes from pacman install time
    # and end up in the cpio with varying values. Rewriting at the
    # cpio-byte level avoids touching the source filesystem (which on
    # overlayfs would trigger copy-up and break hardlinks).
    python3 /tmp/cache22-build/scripts/normalize-initramfs-mtimes.py \
        "/usr/lib/modules/${kver}/initramfs.img" "$SDE"
done

echo "==> Initramfs generation complete"
