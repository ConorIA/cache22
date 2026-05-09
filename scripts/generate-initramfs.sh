#!/usr/bin/env bash
# Build dracut initramfs for every installed kernel. dracut (not
# mkinitcpio) because bootc/composefs/ostree's dracut hooks are what we
# rely on. patch-ostree-dracut.sh runs first so the bootc module
# actually installs.

set -euo pipefail

echo "==> Generating dracut initramfs for installed kernels"

# dracut --reproducible doesn't overwrite the mtimes of files it pulls
# into the cpio — it preserves whatever the source filesystem had. Files
# installed by pacman get wall-clock mtimes from install time, so two
# back-to-back builds produce initramfs cpios with different per-entry
# mtimes (millions of differing bytes for one 6-byte size delta). Pin
# the mtimes here so dracut sees a deterministic source tree.
SDE="${SOURCE_DATE_EPOCH:-0}"
echo "==> Pinning mtimes under /usr /etc /var/lib /opt to SDE=$SDE"
for d in /usr /etc /var/lib /opt; do
    [[ -d "$d" ]] || continue
    find "$d" -exec touch --no-dereference --date="@$SDE" {} + 2>/dev/null || true
done

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
done

echo "==> Initramfs generation complete"
