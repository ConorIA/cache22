#!/usr/bin/env bash
# Local determinism test for the cache22 rechunker.
#
# Pulls the latest rolling image of one variant (default: arch-server),
# runs the rechunker against it twice, and diffs the resulting OCI
# manifests. If everything is deterministic, both runs produce identical
# layer digests.
#
# This DOES NOT exercise the buildah-bud half of the pipeline — for that
# you'd need to run `buildah bud --no-cache` twice (~80 min). Most of
# our determinism work has been in the rechunker, so this is the fast
# iteration loop.
#
# Usage:
#   scripts/test-determinism.sh [variant]
#       variant defaults to arch-server.
#
# Runtime: ~10-20 min (two zstd-19 rechunker passes).

set -euo pipefail

VARIANT="${1:-arch-server}"
IMAGE="ghcr.io/cmspam/cache22-${VARIANT}:rolling"
WORK=/tmp/cache22-determinism-test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Variant: $VARIANT"
echo "==> Workdir: $WORK"

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Pulling $IMAGE into local containers-storage"
sudo podman pull "$IMAGE" >/dev/null

# Tag locally with the name our rechunker expects (localhost/cache22-${VARIANT}:raw)
LOCAL_REF="localhost/cache22-${VARIANT}:raw"
sudo podman tag "$IMAGE" "$LOCAL_REF"

# Run rechunker twice, into two separate OCI output dirs
for i in 1 2; do
    OUT="$WORK/oci-$i"
    echo "==> Rechunker run #$i → $OUT"
    sudo python3 "$SCRIPT_DIR/rechunk-cache22.py" \
        --src "$LOCAL_REF" \
        --dst "$OUT" \
        --source-date-epoch 0 \
        --image-created-epoch 0 \
        2>&1 | tail -25
done

echo
echo "==> Comparing manifests"
python3 <<'PY'
import json
import sys
from pathlib import Path

work = Path("/tmp/cache22-determinism-test")
manifests = []
for i in (1, 2):
    idx = json.loads((work / f"oci-{i}/index.json").read_text())
    mref = idx["manifests"][0]["digest"].removeprefix("sha256:")
    m = json.loads((work / f"oci-{i}/blobs/sha256/{mref}").read_text())
    manifests.append((i, m))

m1 = manifests[0][1]; m2 = manifests[1][1]
l1 = [(l["digest"], l["size"]) for l in m1["layers"]]
l2 = [(l["digest"], l["size"]) for l in m2["layers"]]
s1 = {d for d, _ in l1}
s2 = {d for d, _ in l2}
shared = s1 & s2
only1 = [(d, s) for d, s in l1 if d not in s2]
only2 = [(d, s) for d, s in l2 if d not in s1]

def fmt(n): return f"{n/1024/1024:.2f} MiB"

print(f"run 1: {len(l1)} layers, {fmt(sum(s for _, s in l1))}")
print(f"run 2: {len(l2)} layers, {fmt(sum(s for _, s in l2))}")
print(f"shared layer digests: {len(shared)} / {len(l1)}")
print(f"only-in-1: {len(only1)}, only-in-2: {len(only2)}")

if not only1 and not only2:
    print()
    print("⭐ RECHUNKER IS DETERMINISTIC ⭐")
    sys.exit(0)
else:
    print()
    print("DRIFT DETECTED:")
    for d, s in sorted(only1, key=lambda x: -x[1]):
        print(f"  only-in-1: {fmt(s):>12}  {d[:25]}")
    for d, s in sorted(only2, key=lambda x: -x[1]):
        print(f"  only-in-2: {fmt(s):>12}  {d[:25]}")
    sys.exit(1)
PY
