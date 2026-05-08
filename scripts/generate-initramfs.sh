#!/usr/bin/env bash
# Build dracut initramfs for every installed kernel. dracut (not
# mkinitcpio) because bootc/composefs/ostree's dracut hooks are what we
# rely on. patch-ostree-dracut.sh runs first so the bootc module
# actually installs.

set -euo pipefail

echo "==> Generating dracut initramfs for installed kernels"

shopt -s nullglob
for kver_dir in /usr/lib/modules/*/; do
    kver="$(basename "${kver_dir}")"
    if [[ ! -f "${kver_dir}vmlinuz" ]]; then
        echo "    skipping ${kver} (no vmlinuz)"
        continue
    fi
    echo "    building initramfs for ${kver}"
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
