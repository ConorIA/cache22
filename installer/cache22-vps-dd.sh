#!/usr/bin/env bash
# cache22-vps-dd.sh — install cache22 onto a VPS by flashing the prebuilt
# DD image, using the 'reinstall' tool as the low-RAM dd transport.
#
# Run this on the VPS's existing OS (as root). It:
#   1. resolves the prebuilt cache22 disk image release URL,
#   2. downloads the 'reinstall' tool,
#   3. flashes the image with reinstall's dd mode (works in ~256-512 MB
#      RAM — it streams the image straight to disk, no multi-GB scratch),
#      pausing afterwards so credentials can be injected,
#   4. prints the one command to set your SSH key / password / hostname
#      on the freshly written disk before the first boot.
#
# The image boots a hardened default account 'cache' (password 'cache',
# expired, console-only — network SSH password auth is disabled) and grows
# itself to fill the disk on first boot. Inject your own key/password with
# step 4 for headless access, or use the provider console for first login.

set -euo pipefail

REPO="cmspam/cache22"
VARIANT="arch-server"
TAG="latest"
SSH_KEY=""
PASSWORD=""
HOSTNAME_NEW=""
REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main/installer"

usage() {
    cat <<EOF
Usage: $0 [--variant <id>] [--tag <release>] [--ssh-key <key|@file|gh:user>]
          [--password <pw>] [--hostname <name>]

  --variant   server variant: arch-server (default) or cachy-server
  --tag       release tag to pull the image from (default: latest)
  --ssh-key   SSH public key to install for headless access
  --password  new password for the default 'cache' user
  --hostname  system hostname

Server variants only. The image is BIOS/GRUB, no Secure Boot, no LUKS.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)  VARIANT="$2"; shift 2 ;;
        --tag)      TAG="$2"; shift 2 ;;
        --ssh-key)  SSH_KEY="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --hostname) HOSTNAME_NEW="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] || { echo "Must run as root." >&2; exit 1; }
case "$VARIANT" in
    arch-server|cachy-server) ;;
    *) echo "Unsupported variant '$VARIANT' (arch-server or cachy-server)." >&2; exit 1 ;;
esac

IMG_NAME="cache22-${VARIANT}-bios.raw.zst"
if [[ "$TAG" == "latest" ]]; then
    IMG_URL="https://github.com/${REPO}/releases/latest/download/${IMG_NAME}"
else
    IMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${IMG_NAME}"
fi

echo "==> cache22 VPS install"
echo "    variant: $VARIANT"
echo "    image:   $IMG_URL"
echo

WORK="$(mktemp -d)"
echo "==> Fetching reinstall tool"
curl -fsSL "$REINSTALL_URL" -o "$WORK/reinstall.sh"

# Build the credential-injection one-liner shown after dd. reinstall's own
# --ssh-key/--password do not work on cache22's ostree layout, so we use
# cache22-inject.sh, which writes into the deployment's /etc and home.
inject_args=()
[[ -n "$SSH_KEY" ]]      && inject_args+=(--ssh-key "'$SSH_KEY'")
[[ -n "$PASSWORD" ]]     && inject_args+=(--password "'$PASSWORD'")
[[ -n "$HOSTNAME_NEW" ]] && inject_args+=(--hostname "'$HOSTNAME_NEW'")

cat <<EOF

═══════════════════════════════════════════════════════════════════
  About to flash $IMG_NAME onto this machine with reinstall dd mode.
  reinstall will reboot into a small in-RAM environment, stream the
  image to disk, then PAUSE (so this box stays reachable on its
  current IP and SSH keys).

  AFTER it pauses, reconnect over SSH and run:

    curl -fsSL ${RAW_BASE}/cache22-inject.sh | bash -s -- ${inject_args[*]:-<your --ssh-key / --password / --hostname>}
    reboot

  cache22 then boots, grows to fill the disk, and you log in with the
  key/password you injected (or via the provider console as cache/cache).
═══════════════════════════════════════════════════════════════════

EOF
read -rp "Proceed with flashing? Type YES to continue: " ans
[[ "$ans" == "YES" ]] || { echo "Aborted."; exit 0; }

# --hold 2 pauses after dd completes, before reboot, leaving the box
# reachable so cache22-inject.sh can run against the written disk.
exec bash "$WORK/reinstall.sh" dd --img "$IMG_URL" --hold 2
