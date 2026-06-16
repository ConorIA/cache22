#!/bin/sh
# cache22-alpine-install.sh — run INSIDE the reinstall "alpine --hold 1"
# Live-OS environment (in-RAM Alpine, target disk free) to install cache22
# by streaming the prebuilt disk image from ghcr.io straight onto the disk.
#
# It streams the image (never stored uncompressed), injects an SSH key into
# the ostree deployment so the box is reachable headless on first boot, and
# reboots. The image grows to fill the disk on first boot.
#
#   curl -fsSL <raw>/cache22-alpine-install.sh | sh -s -- \
#       --variant cachy-server --ssh-key gh:cmspam
set -eu

VARIANT="cachy-server"
SSH_KEY=""
DISK=""
USER_NAME="cache"

while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        --disk)    DISK="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

echo "==> Installing tools"
apk add --quiet curl jq zstd btrfs-progs blkid openssl bash >/dev/null
modprobe btrfs 2>/dev/null || true

# Resolve the SSH key form.
case "$SSH_KEY" in
    gh:*) SSH_KEY="$(curl -fsSL "https://github.com/${SSH_KEY#gh:}.keys" | head -1)" ;;
    gl:*) SSH_KEY="$(curl -fsSL "https://gitlab.com/${SSH_KEY#gl:}.keys" | head -1)" ;;
esac
[ -n "$SSH_KEY" ] || { echo "An --ssh-key is required for headless install." >&2; exit 1; }

# Pick the target disk: largest real block device if not given.
if [ -z "$DISK" ]; then
    name="$(lsblk -dnro NAME,TYPE,SIZE 2>/dev/null | awk '$2=="disk"{print $1}' | head -1)"
    [ -n "$name" ] || name="$(ls /sys/block | grep -Ev '^(loop|sr|ram)' | head -1)"
    DISK="/dev/$name"
fi
[ -b "$DISK" ] || { echo "Target disk $DISK not found." >&2; exit 1; }
echo "==> Target disk: $DISK"

# Stream the image from ghcr (anonymous, public) straight to the disk.
REPO="cmspam/cache22-${VARIANT}-dd"
echo "==> Resolving ghcr.io/${REPO}:rolling"
TOKEN="$(curl -fsSL "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO}:pull" | jq -r '.token')"
MANIFEST="$(curl -fsSL -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://ghcr.io/v2/${REPO}/manifests/rolling")"
DIGEST="$(echo "$MANIFEST" | jq -r '.layers[] | select(.mediaType|test("octet-stream|zstd")) | .digest' | head -1)"
[ -n "$DIGEST" ] || DIGEST="$(echo "$MANIFEST" | jq -r '.layers[0].digest')"
echo "==> Streaming ${DIGEST} -> ${DISK}"
curl -fL --progress-bar -H "Authorization: Bearer ${TOKEN}" \
    "https://ghcr.io/v2/${REPO}/blobs/${DIGEST}" | zstd -d | dd of="$DISK" bs=4M status=progress
sync
# Re-read the partition table written by dd.
partprobe "$DISK" 2>/dev/null || blockdev --rereadpt "$DISK" 2>/dev/null || true
sleep 2

# Inject the SSH key into the ostree deployment + the user's home subvol.
echo "==> Injecting SSH key for ${USER_NAME}"
ROOT_PART="$(blkid -t LABEL=cache22-root -o device | head -1)"
[ -n "$ROOT_PART" ] || ROOT_PART="$(ls "${DISK}"*3 "${DISK}"p3 2>/dev/null | head -1)"
mnt=/tmp/c22root
mkdir -p "$mnt"
mount -o subvol=root "$ROOT_PART" "$mnt"
DEPLOY_ETC="$(find "$mnt/ostree/deploy" -mindepth 3 -maxdepth 3 -type d -name '*.0' ! -path '*/backing/*' | head -1)/etc"
[ -d "$DEPLOY_ETC" ] || { echo "Could not find deployment /etc" >&2; exit 1; }

homemnt=/tmp/c22home
mkdir -p "$homemnt"
mount -o subvol=home "$ROOT_PART" "$homemnt"
install -d -m 0700 "$homemnt/${USER_NAME}/.ssh"
printf '%s\n' "$SSH_KEY" >> "$homemnt/${USER_NAME}/.ssh/authorized_keys"
chmod 0600 "$homemnt/${USER_NAME}/.ssh/authorized_keys"
chown -R 1000:1000 "$homemnt/${USER_NAME}/.ssh"
umount "$homemnt"

# Key root too (/root -> /var/roothome in the stateroot var); root login
# is key-only (PermitRootLogin prohibit-password).
RH="$(ls -d "$mnt"/ostree/deploy/*/var/roothome 2>/dev/null | head -1)"
[ -n "$RH" ] || RH="$(ls -d "$mnt"/ostree/deploy/*/var 2>/dev/null | head -1)/roothome"
if [ -n "$RH" ]; then
    install -d -m 0700 "$RH/.ssh"
    printf '%s\n' "$SSH_KEY" >> "$RH/.ssh/authorized_keys"
    chmod 0600 "$RH/.ssh/authorized_keys"
    chown -R 0:0 "$RH/.ssh"
fi
# Un-expire cache so key login is not interrupted by a forced change.
days=$(( $(date +%s) / 86400 ))
sed -i "s/^\(${USER_NAME}:[^:]*\):0:/\1:${days}:/" "$DEPLOY_ETC/shadow"
umount "$mnt"
sync

echo "==> Done. Rebooting into cache22."
echo "    SSH in as ${USER_NAME}@<this-ip> with your key once it is up."
reboot
