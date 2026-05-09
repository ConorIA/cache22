#!/usr/bin/env bash
# Local determinism test for the FULL buildah-bud half of the pipeline.
#
# Builds the cache22 raw image twice with --no-cache and compares the
# resulting layer digests. buildah produces one layer per Containerfile
# RUN step, each content-addressed by sha256 of its tar diff. If both
# builds produce the same digest list, the rootfs is byte-identical
# pre-rechunk — i.e., everything inside the container build (pacman,
# system_files overlay, generate-initramfs.sh, sign-secureboot.sh,
# finalize-image.sh) is reproducible.
#
# This catches buildah-bud non-determinism (initramfs, signing, finalize
# scripts) which scripts/test-determinism.sh (rechunker-only) misses.
#
# Usage:
#   scripts/test-buildah-determinism.sh [variant]
#       variant defaults to arch-server.
#       Set SBKEY=/path/to/sb.pem to use a real signing key (else
#       sign-secureboot.sh skips signing — fine for determinism testing).
#
# Runtime: ~30-40 min total (two ~15-20 min --no-cache buildah runs).
# Rebuilds use no cache to actually exercise the pipeline.
#
# Caveat: pacman pulls from live mirrors. If a package version changes
# between the two builds (rare in a 30-min window) the test will show
# spurious drift. For a clean test, run during a quiet period or
# pre-cache the packages.

set -euo pipefail

VARIANT="${1:-arch-server}"
SBKEY="${SBKEY:-/dev/null}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$VARIANT" in
    cachy-*) FAMILY=cachy; BASE=docker.io/cachyos/cachyos-v3 ;;
    arch-*)  FAMILY=arch;  BASE=docker.io/archlinux ;;
    *) echo "unknown variant: $VARIANT" >&2; exit 2 ;;
esac
TYPE=${VARIANT##*-}

cd "$REPO"

if [[ ! -s "$SBKEY" ]]; then
    echo "==> No SB key (SBKEY=$SBKEY); sign-secureboot.sh will skip signing"
    SBKEY=$(mktemp); trap "rm -f $SBKEY" EXIT
fi

LOG="/tmp/cache22-buildah-test.log"
: > "$LOG"

for i in 1 2; do
    echo "============================================================"
    echo "==> Build $i of 2 (variant=$VARIANT, --no-cache)"
    echo "============================================================"
    SECONDS=0
    sudo buildah bud \
        --no-cache \
        --secret id=sbkey,src="$SBKEY" \
        --build-arg BASE_IMAGE="$BASE" \
        --build-arg VARIANT_FAMILY="$FAMILY" \
        --build-arg VARIANT_TYPE="$TYPE" \
        --build-arg VARIANT="$VARIANT" \
        --build-arg SOURCE_DATE_EPOCH=0 \
        --tag "localhost/cache22-test-$i:raw" \
        -f Containerfile \
        . 2>&1 | tee -a "$LOG" | tail -3
    echo "==> Build $i finished in ${SECONDS}s"
done

echo
echo "============================================================"
echo "==> Layer digest comparison"
echo "============================================================"
for i in 1 2; do
    sudo podman inspect "localhost/cache22-test-$i:raw" \
        --format '{{range .RootFS.Layers}}{{println .}}{{end}}' \
        > "/tmp/cache22-layers-$i.txt"
done

if diff -q /tmp/cache22-layers-1.txt /tmp/cache22-layers-2.txt > /dev/null; then
    echo
    echo "⭐ BUILDAH-BUD IS DETERMINISTIC ⭐"
    echo "All $(wc -l < /tmp/cache22-layers-1.txt) layers byte-identical between two --no-cache builds."
    exit 0
else
    echo
    echo "DRIFT DETECTED. Layer digest diff:"
    diff /tmp/cache22-layers-1.txt /tmp/cache22-layers-2.txt
    echo
    echo "Layers numbered top-down; the first divergent line is the first non-deterministic RUN step."
    echo "To find which Containerfile RUN that corresponds to:"
    echo "  sudo podman history localhost/cache22-test-1:raw"
    exit 1
fi
