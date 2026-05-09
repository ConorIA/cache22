#!/usr/bin/env bash
# Tightly-scoped determinism test for the DKMS module build path.
#
# Pulls the latest rolling image of one variant, drops into it, force-
# rebuilds every DKMS module twice, compares the resulting .ko bytes.
# This isolates DKMS reproducibility (kernel-build, signing, kbuild env)
# from the full Containerfile pipeline. Runs in a few minutes.
#
# Usage:
#   scripts/test-dkms-determinism.sh [variant]
#       variant defaults to cachy-server.

set -euo pipefail

VARIANT="${1:-cachy-server}"
IMAGE="ghcr.io/cmspam/cache22-${VARIANT}:rolling"

echo "==> Variant: $VARIANT"
echo "==> Pulling $IMAGE"
sudo podman pull "$IMAGE" >/dev/null

# Build twice in fresh containers, dump wl.ko bytes from each
for i in 1 2; do
    OUT="/tmp/dkms-test-$i"
    rm -rf "$OUT"; mkdir -p "$OUT"
    echo "==> DKMS build run $i"
    sudo podman run --rm --network=host -v "$OUT:/out:Z" --entrypoint=/bin/sh "$IMAGE" -c '
        set -e
        KVER=$(ls /usr/lib/modules | head -1)
        # Wipe any pre-existing built modules so the test forces a real
        # rebuild from scratch each time.
        rm -rf /var/lib/dkms/* /usr/lib/modules/$KVER/updates/dkms 2>/dev/null || true
        # Build each /usr/src/<pkg>-<ver>/ source. The pkg name is the
        # part before the first version-looking segment.
        for src in /usr/src/*/; do
            base=$(basename "$src")
            # Match "<name>-<digits-and-dots>" splitting at the first numeric segment.
            if [[ "$base" =~ ^(.+)-([0-9].*)$ ]]; then
                pkg=${BASH_REMATCH[1]}
                ver=${BASH_REMATCH[2]}
            else
                continue
            fi
            [[ -f "$src/dkms.conf" ]] || continue
            echo "    rebuilding $pkg/$ver for $KVER"
            dkms install --force --no-depmod "$pkg/$ver" -k "$KVER" 2>&1 | tail -3
        done
        echo "==> built modules:"
        # DKMS may put modules at updates/dkms or at the location set by
        # DEST_MODULE_LOCATION in dkms.conf (e.g. kernel/drivers/...).
        # Find any built .ko by searching var/lib/dkms which is the
        # canonical build output regardless of install location.
        find /var/lib/dkms -name "*.ko" -o -name "*.ko.zst" 2>/dev/null | while read ko; do
            # Use parent dir to disambiguate (e.g. broadcom-wl, nvidia)
            pkg=$(echo "$ko" | sed -n "s|.*dkms/\([^/]*\)/.*|\1|p")
            cp "$ko" "/out/${pkg}-$(basename "$ko")"
            echo "  copied: ${pkg}-$(basename "$ko") ($(stat -c%s "$ko"))"
        done
    ' 2>&1 | tail -15
done

echo
echo "==> Comparing module bytes"
DRIFT=0
for f in /tmp/dkms-test-1/*; do
    name=$(basename "$f")
    a="/tmp/dkms-test-1/$name"
    b="/tmp/dkms-test-2/$name"
    if [[ ! -f "$b" ]]; then
        echo "  ⚠ $name: only in run 1"; DRIFT=$((DRIFT+1)); continue
    fi
    sha_a=$(sha256sum "$a" | cut -d' ' -f1)
    sha_b=$(sha256sum "$b" | cut -d' ' -f1)
    if [[ "$sha_a" == "$sha_b" ]]; then
        echo "  ✓ $name (byte-identical)"
    else
        echo "  ✗ $name (DRIFT: $sha_a vs $sha_b, sizes $(stat -c%s "$a") vs $(stat -c%s "$b"))"
        DRIFT=$((DRIFT+1))
    fi
done

if (( DRIFT == 0 )); then
    echo
    echo "⭐ DKMS build is deterministic for $VARIANT ⭐"
else
    echo
    echo "$DRIFT module(s) drifted between two builds"
    exit 1
fi
