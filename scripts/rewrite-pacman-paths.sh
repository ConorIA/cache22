#!/usr/bin/env bash
# Move pacman state from /var to /usr/lib/sysimage so it ships inside the
# immutable image. Same trick as bootcrew/mono / Fedora's /usr/share/rpm.

set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"
SYSIMAGE="/usr/lib/sysimage/pacman"

echo "==> Rewriting pacman paths in ${PACMAN_CONF}"
mkdir -p "${SYSIMAGE}"

if [[ -d /var/lib/pacman && ! -L /var/lib/pacman ]]; then
    cp -a /var/lib/pacman/. "${SYSIMAGE}/"
    rm -rf /var/lib/pacman
fi

if [[ -d /var/cache/pacman/pkg && ! -L /var/cache/pacman/pkg ]]; then
    mkdir -p "${SYSIMAGE}/pkg"
    cp -a /var/cache/pacman/pkg/. "${SYSIMAGE}/pkg/"
    rm -rf /var/cache/pacman
fi

if [[ -d /etc/pacman.d/gnupg && ! -L /etc/pacman.d/gnupg ]]; then
    mkdir -p "${SYSIMAGE}/gnupg"
    cp -a /etc/pacman.d/gnupg/. "${SYSIMAGE}/gnupg/"
fi

mkdir -p "${SYSIMAGE}/hooks"

sed -i \
    -e 's|^#\?\s*DBPath\s*=.*|DBPath      = /usr/lib/sysimage/pacman/|' \
    -e 's|^#\?\s*CacheDir\s*=.*|CacheDir    = /usr/lib/sysimage/pacman/pkg/|' \
    -e 's|^#\?\s*LogFile\s*=.*|LogFile     = /usr/lib/sysimage/pacman/pacman.log|' \
    -e 's|^#\?\s*GPGDir\s*=.*|GPGDir      = /usr/lib/sysimage/pacman/gnupg/|' \
    -e 's|^#\?\s*HookDir\s*=.*|HookDir     = /usr/lib/sysimage/pacman/hooks/|' \
    "${PACMAN_CONF}"

sed -i 's|=\s*/var/lib/pacman|= /usr/lib/sysimage/pacman/|g' "${PACMAN_CONF}"
sed -i 's|=\s*/var/cache/pacman|= /usr/lib/sysimage/pacman/|g' "${PACMAN_CONF}"

# DownloadUser=alpm wouldn't exist consistently in the build env.
sed -i '/^DownloadUser/d' "${PACMAN_CONF}"

# The dkms install scriptlet requests network access. pacman's scriptlet
# sandbox refuses to grant it ("refusing to run ... with network access")
# and skips the scriptlet, so DKMS modules (r8152, broadcom-wl, xone)
# never compile into /usr/lib/modules/<kver>/updates/dkms and ship absent.
# DisableSandboxNetwork lets the scriptlet run so the modules bake in.
if ! grep -q '^DisableSandboxNetwork' "${PACMAN_CONF}"; then
    sed -i '/^\[options\]/a DisableSandboxNetwork' "${PACMAN_CONF}"
fi

echo "==> Pacman state moved to ${SYSIMAGE}; conf rewritten"
grep -E '^\s*(DBPath|CacheDir|LogFile|GPGDir|HookDir)' "${PACMAN_CONF}" || true
