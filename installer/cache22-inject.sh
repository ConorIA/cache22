#!/usr/bin/env bash
# cache22-inject.sh — set SSH key / password / hostname on a freshly
# flashed cache22 DD image.
#
# Run this in the post-dd environment (e.g. the 'reinstall --hold 2'
# Alpine shell) while the target disk is written but not yet booted. It
# locates the cache22 root by GPT label, mounts the deployment, and writes
# the credentials into the ostree deployment's /etc and the user's home —
# the places an ostree/bootc system actually reads. The image's own
# first-boot service grows the filesystem to fill the disk, so this script
# does not resize anything.
#
# This is separate from the 'reinstall' tool's built-in --ssh-key/
# --password injection, which writes to a top-level /etc and /root and so
# has no effect on an ostree layout.

set -euo pipefail

SSH_KEY=""
PASSWORD=""
HOSTNAME_NEW=""
DISK=""
USER_NAME="cache"
MNT="/tmp/cache22-target"

usage() {
    cat <<EOF
Usage: $0 [--ssh-key <key|@file>] [--password <pw>] [--hostname <name>] [--disk <dev>] [--user <name>]

  --ssh-key   public key string, or @/path/to/file. Added to the user's authorized_keys.
  --password  new password for the default user (replaces the public default).
  --hostname  system hostname.
  --disk      target disk (default: autodetect by the cache22-root GPT label).
  --user      account to configure (default: $USER_NAME).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-key)  SSH_KEY="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --hostname) HOSTNAME_NEW="$2"; shift 2 ;;
        --disk)     DISK="$2"; shift 2 ;;
        --user)     USER_NAME="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] || { echo "Must run as root." >&2; exit 1; }
for t in blkid btrfs openssl curl; do
    command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

# Resolve the key form: @file, gh:<user> / gl:<user>, an https URL, or a
# literal key string.
case "$SSH_KEY" in
    "")            ;;
    @*)            SSH_KEY="$(cat "${SSH_KEY#@}")" ;;
    gh:*)          SSH_KEY="$(curl -fsSL "https://github.com/${SSH_KEY#gh:}.keys")" ;;
    gl:*)          SSH_KEY="$(curl -fsSL "https://gitlab.com/${SSH_KEY#gl:}.keys")" ;;
    https://*)     SSH_KEY="$(curl -fsSL "$SSH_KEY")" ;;
esac
[[ -z "$SSH_KEY" || "$SSH_KEY" == ssh-* || "$SSH_KEY" == ecdsa-* || "$SSH_KEY" == sk-* ]] \
    || { echo "Resolved SSH key does not look like a public key." >&2; exit 1; }

# Resolve the root partition by GPT label.
udevadm settle 2>/dev/null || true
ROOT_PART="$DISK"
if [[ -z "$ROOT_PART" ]]; then
    ROOT_PART="$(readlink -f /dev/disk/by-partlabel/cache22-root 2>/dev/null || true)"
fi
[[ -b "$ROOT_PART" ]] || { echo "Could not find cache22-root partition (pass --disk)." >&2; exit 1; }
echo "==> cache22 root partition: $ROOT_PART"

mkdir -p "$MNT"
cleanup() { umount -R "$MNT" 2>/dev/null || true; }
trap cleanup EXIT

# Mount the deployment (root subvol) and the user-data (home subvol).
mount -o subvol=root "$ROOT_PART" "$MNT"

# Locate the writable per-deploy /etc (same logic as the installer).
DEPLOY_ETC=""
if [[ -d "$MNT/ostree/deploy" ]]; then
    DEPLOY_ETC="$(find "$MNT/ostree/deploy" -mindepth 3 -maxdepth 3 -type d -name '*.0' \
        ! -path '*/backing/*' 2>/dev/null | head -1)/etc"
fi
[[ -d "$DEPLOY_ETC" ]] || { echo "Could not locate deployment /etc under $MNT" >&2; exit 1; }
echo "==> deployment /etc: $DEPLOY_ETC"

if [[ -n "$HOSTNAME_NEW" ]]; then
    echo "$HOSTNAME_NEW" > "$DEPLOY_ETC/hostname"
    echo "==> hostname set to $HOSTNAME_NEW"
fi

if [[ -n "$PASSWORD" ]]; then
    hashed="$(openssl passwd -6 "$PASSWORD")"
    days="$(( $(date +%s) / 86400 ))"
    # Replace the user's hash+lastchange in place (account already exists).
    sed -i -E "s|^(${USER_NAME}:)[^:]*:[0-9]*:|\1${hashed//|/\\|}:${days}:|" "$DEPLOY_ETC/shadow"
    echo "==> password updated for $USER_NAME"
fi

if [[ -n "$SSH_KEY" ]]; then
    # Home lives in the 'home' subvol, mounted at /var/home in the running
    # system. Mount it directly to drop authorized_keys.
    HOME_MNT="$MNT.home"
    mkdir -p "$HOME_MNT"
    mount -o subvol=home "$ROOT_PART" "$HOME_MNT"
    sshdir="$HOME_MNT/${USER_NAME}/.ssh"
    install -d -m 0700 "$sshdir"
    printf '%s\n' "$SSH_KEY" >> "$sshdir/authorized_keys"
    chmod 0600 "$sshdir/authorized_keys"
    # uid/gid 1000 = the default cache22 primary user.
    chown -R 1000:1000 "$HOME_MNT/${USER_NAME}/.ssh"
    umount "$HOME_MNT"; rmdir "$HOME_MNT"
    echo "==> SSH key added for $USER_NAME"
fi

sync
echo "==> Injection complete. Reboot the machine to start cache22."
