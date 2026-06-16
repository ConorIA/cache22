#!/usr/bin/env bash
# cache22-flash.sh — download a prebuilt cache22 disk image from ghcr.io
# and write it to a local disk.
#
# The image is stored as an OCI artifact next to the container image and
# streamed straight to the target disk: it is never stored uncompressed on
# the way, so writing a multi-GB image needs no scratch space. On first
# boot the system grows its filesystem to fill the disk.
#
# The image is legacy-BIOS/GRUB (no Secure Boot, no UKI, no LUKS) and is
# server variants only. A UEFI-only machine will not boot it; use the ISO
# installer there instead.
#
# Example:
#   sudo cache22-flash.sh --variant arch-server --disk /dev/sdX

set -euo pipefail

REGISTRY="ghcr.io"
NAMESPACE="cmspam"
VARIANT="arch-server"
TAG="rolling"
DISK=""
ASSUME_YES=0

usage() {
    cat <<EOF
Usage: sudo $0 --disk <device> [--variant <id>] [--tag <tag>] [--yes]

  --disk      target disk to overwrite, e.g. /dev/sdb (required)
  --variant   server variant: arch-server (default) or cachy-server
  --tag       image tag (default: rolling)
  --yes       skip the confirmation prompt
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)    DISK="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        --tag)     TAG="$2"; shift 2 ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] || { echo "Must run as root." >&2; exit 1; }
[[ -n "$DISK" ]] || { echo "--disk is required." >&2; usage; exit 1; }
[[ -b "$DISK" ]] || { echo "$DISK is not a block device." >&2; exit 1; }
case "$VARIANT" in
    arch-server|cachy-server) ;;
    *) echo "Unsupported variant '$VARIANT' (arch-server or cachy-server)." >&2; exit 1 ;;
esac
for t in curl jq zstd dd; do
    command -v "$t" >/dev/null 2>&1 || { echo "Missing required tool: $t" >&2; exit 1; }
done

REPO="${NAMESPACE}/cache22-${VARIANT}-dd"

# ── Resolve the image blob in the registry ──────────────────────────────
echo "==> Resolving ${REGISTRY}/${REPO}:${TAG}"
TOKEN="$(curl -fsSL "https://${REGISTRY}/token?service=${REGISTRY}&scope=repository:${REPO}:pull" | jq -r '.token')"
[[ -n "$TOKEN" && "$TOKEN" != "null" ]] || { echo "Could not get a pull token for ${REPO}." >&2; exit 1; }

MANIFEST="$(curl -fsSL \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json" \
    "https://${REGISTRY}/v2/${REPO}/manifests/${TAG}")"

# The disk image is the (only) non-config layer.
DIGEST="$(echo "$MANIFEST" | jq -r '.layers[] | select(.mediaType | test("octet-stream|zstd")) | .digest' | head -1)"
[[ -n "$DIGEST" ]] || DIGEST="$(echo "$MANIFEST" | jq -r '.layers[0].digest')"
SIZE="$(echo "$MANIFEST" | jq -r --arg d "$DIGEST" '.layers[] | select(.digest==$d) | .size')"
[[ "$DIGEST" == sha256:* ]] || { echo "Could not find an image layer in the manifest." >&2; exit 1; }
echo "    layer ${DIGEST} (${SIZE:-?} bytes compressed)"

# ── Confirm the destination ─────────────────────────────────────────────
echo
echo "About to OVERWRITE ${DISK}:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$DISK" 2>/dev/null || lsblk "$DISK"
echo
if (( ! ASSUME_YES )); then
    read -rp "Type YES to write cache22-${VARIANT} to ${DISK}: " ans
    [[ "$ans" == "YES" ]] || { echo "Aborted."; exit 0; }
fi

# ── Stream blob -> decompress -> disk ───────────────────────────────────
echo "==> Writing (streamed, no scratch space used)"
curl -fsSL -H "Authorization: Bearer ${TOKEN}" \
    "https://${REGISTRY}/v2/${REPO}/blobs/${DIGEST}" \
  | zstd -d | dd of="$DISK" bs=4M conv=fsync status=progress
sync

echo
echo "==> Done. cache22-${VARIANT} written to ${DISK}."
echo "    It grows to fill the disk on first boot. Log in on the console as"
echo "    cache / cache (you must change the password; that also enables SSH)."
