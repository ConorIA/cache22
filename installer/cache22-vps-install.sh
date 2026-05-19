#!/usr/bin/env bash
# cache22-vps-install — bootstrap cache22 onto a VPS via kexec.
#
# Downloads the NixOS-based kexec installer image from the latest
# cache22 release, extracts it into /root/, and runs the kexec
# transition. After the in-place reboot, SSH back in as root and run
#   cache22-install
# to install cache22 onto the VPS's disk.
#
# Usage (from the VPS's existing OS, as root):
#   curl -fsSL https://raw.githubusercontent.com/cmspam/cache22/main/installer/cache22-vps-install.sh | sudo bash
#
# Or pin to a specific release:
#   sudo TAG=iso-2026-05-19 bash <(curl -fsSL https://raw.githubusercontent.com/cmspam/cache22/main/installer/cache22-vps-install.sh)

set -euo pipefail

REPO="cmspam/cache22"
ASSET="cache22-kexec-vps.tar.xz"
TAG="${TAG:-latest}"
DEST="/root"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must run as root (kexec syscall needs CAP_SYS_BOOT)" >&2
    exit 1
fi

if [[ "$TAG" == "latest" ]]; then
    URL="https://github.com/${REPO}/releases/latest/download/${ASSET}"
else
    URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
fi

if ! command -v kexec >/dev/null 2>&1; then
    echo "==> kexec not installed; installing kexec-tools"
    if   command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y kexec-tools
    elif command -v dnf  >/dev/null 2>&1; then dnf install -y kexec-tools
    elif command -v yum  >/dev/null 2>&1; then yum install -y kexec-tools
    elif command -v apk  >/dev/null 2>&1; then apk add kexec-tools
    elif command -v zypper >/dev/null 2>&1; then zypper --non-interactive install kexec-tools
    elif command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm kexec-tools
    else
        echo "ERROR: don't know how to install kexec-tools on this distro." >&2
        echo "Install it manually, then re-run this script." >&2
        exit 1
    fi
fi

echo "==> Downloading $URL"
curl --fail --location --progress-bar "$URL" \
    | tar -xJf - -C "$DEST"

if [[ ! -x "$DEST/kexec/run" ]]; then
    echo "ERROR: $DEST/kexec/run not found after extraction." >&2
    exit 1
fi

echo "==> Running NixOS kexec transition"
echo "    Your SSH session will drop. Wait 30-60 seconds, then SSH"
echo "    back in as root and run: cache22-install"
exec "$DEST/kexec/run"
