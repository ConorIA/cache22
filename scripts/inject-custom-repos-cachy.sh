#!/usr/bin/env bash
# Configure pacman repos for the CACHY family. Layers cmspam/* on top of
# the cachyos-v3 base + enables [multilib]. See docs/IMAGE_BUILD.md.

set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"

echo "==> Enabling [multilib]"
sed -i '/^\s*#\s*\[multilib\]/,/^\s*#\s*Include\s*=\s*\/etc\/pacman\.d\/mirrorlist/{
    s/^\s*#\s*//
}' "${PACMAN_CONF}"

echo "==> Injecting custom repos at top of pacman.conf"
CUSTOM_REPOS=$(cat <<'EOF'

# cmspam/* — highest priority. Unsigned (--skippgpcheck upstream),
# SigLevel = Optional TrustAll required.

[bootc-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/bootc-v3/releases/download/latest-v3

[qemu-patched-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/qemu-patched/releases/download/latest-v3

[xe-virt-host-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/xe-virt-repo/releases/download/latest-host

# Guest-side patched mesa + intel-media-driver for running cache22 AS a VM
# guest with Intel Xe virtio-gpu native context (GL/Vulkan/VA-API, no
# passthrough). Pairs with xe-virt-host-v3 so one image runs as host or
# guest. Repo-priority placement wins over stock mesa/lib32-mesa/
# intel-media-driver (all already in the package layers).
[xe-virt-guest-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/xe-virt-repo/releases/download/latest-guest

# Patched gamescope: fixes nvidia steam remote-play black screen +
# inverted colors. Repo-priority placement wins over stock cachyos.
[gamescope-patched-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/gamescope-patched/releases/download/latest-v3

# Out-of-tree Intel iavf VF driver (iavf-dkms). Built against the image
# kernel via DKMS; selected over the in-kernel iavf by a depmod override.
[iavf-dkms]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/intel-iavf/releases/download/arch

EOF
)

awk -v block="${CUSTOM_REPOS}" '
    BEGIN { injected = 0 }
    /^\[(core|extra|cachyos|cachyos-v3|cachyos-v4|multilib)\]/ && !injected {
        print block
        injected = 1
    }
    { print }
' "${PACMAN_CONF}" > "${PACMAN_CONF}.new" \
    && mv "${PACMAN_CONF}.new" "${PACMAN_CONF}"

echo "==> Updated [...] sections in order:"
grep -E '^\[' "${PACMAN_CONF}"
