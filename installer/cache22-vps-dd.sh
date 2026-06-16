#!/usr/bin/env bash
# cache22-vps-dd.sh — one-command cache22 install for a VPS.
#
# Run on the VPS's existing OS (as root). It downloads the cache22 fork of
# the reinstall tool, which kexecs into an in-RAM Alpine, streams the
# prebuilt cache22 disk image from ghcr.io straight onto the disk (works in
# ~256-512 MB RAM), injects your SSH key into the deployment, and reboots.
# The system grows to fill the disk on first boot; log in as the 'cache'
# user with your key.
#
# Server variants only; BIOS/GRUB image (no Secure Boot, no LUKS).
#
#   curl -fsSL https://raw.githubusercontent.com/cmspam/cache22/dd-image-installer/installer/cache22-vps-dd.sh \
#     | sudo bash -s -- --variant cachy-server --ssh-key gh:cmspam

set -euo pipefail

BRANCH="dd-image-installer"
NAMESPACE="cmspam"
VARIANT="cachy-server"
TAG="rolling"
SSH_KEY=""
REINSTALL_URL="https://raw.githubusercontent.com/${NAMESPACE}/cache22/${BRANCH}/installer/reinstall/reinstall.sh"

usage() {
    cat <<EOF
Usage: sudo $0 --ssh-key <key|@file|gh:user|gl:user> [--variant <id>] [--tag <tag>]

  --ssh-key   SSH public key for headless access (required)
  --variant   arch-server (default cachy-server) or cachy-server
  --tag       image tag (default: rolling)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        --tag)     TAG="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] || { echo "Must run as root." >&2; exit 1; }
case "$VARIANT" in
    arch-server|cachy-server) ;;
    *) echo "Unsupported variant '$VARIANT'." >&2; exit 1 ;;
esac

# Resolve the SSH key to a single literal key (reinstall stores it for the
# fork's injector). gh:/gl: pull from the user's public keys.
case "$SSH_KEY" in
    "")        echo "--ssh-key is required (headless install)." >&2; exit 1 ;;
    @*)        SSH_KEY="$(head -1 "${SSH_KEY#@}")" ;;
    gh:*)      SSH_KEY="$(curl -fsSL "https://github.com/${SSH_KEY#gh:}.keys" | head -1)" ;;
    gl:*)      SSH_KEY="$(curl -fsSL "https://gitlab.com/${SSH_KEY#gl:}.keys" | head -1)" ;;
esac
[[ -n "$SSH_KEY" ]] || { echo "Could not resolve an SSH key." >&2; exit 1; }

IMG="ghcr://${NAMESPACE}/cache22-${VARIANT}-dd:${TAG}"
echo "==> cache22 VPS install: ${IMG}"

cd /root 2>/dev/null || cd /tmp
curl -fsSL -o reinstall.sh "$REINSTALL_URL"

# dd mode with our ghcr ref. --username root keeps it non-interactive;
# --ssh-key is stashed for the fork's post-dd injector.
exec bash reinstall.sh dd --img "$IMG" --username root --ssh-key "$SSH_KEY"
