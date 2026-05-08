#!/usr/bin/env bash
# Patches against the upstream 50ostree + 51bootc dracut modules:
#
#   1. ${systemdsystemconfdir} is empty on Arch's dracut, so the
#      target.wants symlink ends up at the wrong path → switch_root
#      drops to emergency. Hard-code /etc/systemd/system.
#   2. 51bootc's check() returns 255 → dracut skips it even with
#      force-add. Rewrite to return 0.

set -euo pipefail

CONFDIR=/etc/systemd/system

patch_systemdsystemconfdir() {
    local mod="$1"
    sed -i \
        -e "s|\"\${initdir}\${systemdsystemconfdir}/|\"\${initdir}${CONFDIR}/|g" \
        -e "s|\"\${systemdsystemconfdir}/|\"${CONFDIR}/|g" \
        "$mod"
}

OSTREE=/usr/lib/dracut/modules.d/50ostree/module-setup.sh
BOOTC=/usr/lib/dracut/modules.d/51bootc/module-setup.sh

[[ -f "$OSTREE" ]] || { echo "ERROR: $OSTREE not found"; exit 1; }
[[ -f "$BOOTC" ]]  || { echo "ERROR: $BOOTC not found"; exit 1; }

patch_systemdsystemconfdir "$OSTREE"
patch_systemdsystemconfdir "$BOOTC"

sed -i 's|return 255|return 0|' "$BOOTC"

echo "==> Patched $OSTREE:"
grep -E 'initrd-.*target.wants' "$OSTREE" | head -3 || true
echo "==> Patched $BOOTC:"
grep -E 'return [0-9]+|initrd-.*target.wants' "$BOOTC" | head -5 || true
