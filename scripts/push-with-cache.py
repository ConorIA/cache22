#!/usr/bin/env python3
"""push-with-cache.py — push a rechunked OCI image to ghcr.io, treating
the destination repo itself as the blob cache.

For each layer in the rechunked manifest:
  1. HEAD destination repo. Blob already there (from a prior build) → skip.
  2. Blob bytes present in local OCI dir (cache miss this build, freshly
     compressed) → upload them.
  3. Blob neither in destination nor local → FATAL. Means the pkgcache
     index claimed a blob was in the variant's repo but it isn't. Either
     ghcr.io GC'd it or the index is stale. Delete the GHA cache entry
     for this variant and let the next build re-populate cold.

Then upload the config blob (always local, always fresh per build) and
PUT the manifest at the requested tag.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cache_client import GhcrClient  # noqa: E402


def _read_oci_manifest(oci_dir: Path) -> tuple[dict, dict]:
    """Return (manifest_dict, manifest_descriptor_from_index)."""
    index = json.loads((oci_dir / "index.json").read_text())
    target = None
    for m in index.get("manifests", []):
        ann = m.get("annotations") or {}
        if ann.get("org.opencontainers.image.ref.name") == "rechunked":
            target = m
            break
    if target is None:
        target = index["manifests"][0]
    digest = target["digest"]
    manifest_path = oci_dir / "blobs" / "sha256" / digest.removeprefix("sha256:")
    manifest = json.loads(manifest_path.read_text())
    return manifest, target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="OCI image directory")
    ap.add_argument("--dst-repo", required=True,
                    help="Target ghcr.io repo path, e.g. cmspam/cache22-cachy-server")
    ap.add_argument("--dst-tag", required=True, help="Target tag, e.g. rolling")
    ap.add_argument("--auth-file", default=None,
                    help="docker config.json with ghcr.io creds")
    args = ap.parse_args()

    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
    t_start = time.monotonic()

    oci_dir = Path(args.src)
    manifest, mref = _read_oci_manifest(oci_dir)

    client = GhcrClient.from_authfile(args.auth_file)
    dst_repo = args.dst_repo
    blobs_dir = oci_dir / "blobs" / "sha256"

    n_skip = 0
    n_upload = 0
    bytes_skipped = 0
    bytes_uploaded = 0

    layers = manifest.get("layers", [])
    print(f"==> Pushing {len(layers)} layers + config + manifest "
          f"to ghcr.io/{dst_repo}:{args.dst_tag}")

    for i, layer in enumerate(layers, 1):
        digest = layer["digest"]
        size = layer["size"]
        local_path = blobs_dir / digest.removeprefix("sha256:")

        # 1. Already in destination from a prior build?
        if client.blob_exists(dst_repo, digest):
            n_skip += 1
            bytes_skipped += size
            print(f"  [{i:3d}/{len(layers)}] {digest[:19]}  EXISTS")
            continue

        # 2. Not in destination; do we have local bytes?
        if local_path.exists():
            if not client.blob_upload(dst_repo, local_path, digest):
                sys.exit(f"FATAL: blob upload of {digest} failed")
            n_upload += 1
            bytes_uploaded += size
            print(f"  [{i:3d}/{len(layers)}] {digest[:19]}  UPLOAD ({size:,} bytes)")
            continue

        # 3. Neither — cache lied. Surface a clear error.
        sys.exit(
            f"FATAL: layer {digest} not in destination repo and not in "
            f"local OCI dir. The pkgcache index for this variant probably "
            f"references a blob that ghcr.io has garbage-collected, or the "
            f"index drifted from reality. Delete the GHA cache entry "
            f"'pkgcache-{dst_repo.rsplit('/', 1)[-1].removeprefix('cache22-')}' "
            f"to force a fresh full rebuild on the next run."
        )

    # Config blob (always local, always fresh per build)
    config = manifest["config"]
    config_digest = config["digest"]
    config_path = blobs_dir / config_digest.removeprefix("sha256:")
    if not client.blob_exists(dst_repo, config_digest):
        if not client.blob_upload(dst_repo, config_path, config_digest):
            sys.exit("FATAL: config blob upload failed")
        print(f"  config {config_digest[:19]}  UPLOAD")
    else:
        print(f"  config {config_digest[:19]}  EXISTS")

    # Manifest PUT. Read bytes back from disk so we PUT exactly what was
    # written (preserves JSON byte ordering for digest stability).
    manifest_bytes = (
        blobs_dir / mref["digest"].removeprefix("sha256:")
    ).read_bytes()
    media_type = mref.get("mediaType", "application/vnd.oci.image.manifest.v1+json")
    if not client.manifest_put(dst_repo, args.dst_tag, manifest_bytes, media_type):
        sys.exit("FATAL: manifest PUT failed")
    print(f"  manifest {mref['digest'][:19]}  PUT  -> :{args.dst_tag}")

    elapsed = time.monotonic() - t_start
    mb = lambda b: f"{b / 1024 / 1024:.1f} MiB"  # noqa: E731
    print()
    print(f"=== Push complete in {elapsed:.1f}s ===")
    print(f"    {n_skip:3d} layers already in dest ({mb(bytes_skipped)})")
    print(f"    {n_upload:3d} layers uploaded ({mb(bytes_uploaded)})")


if __name__ == "__main__":
    main()
