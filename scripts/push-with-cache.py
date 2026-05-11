#!/usr/bin/env python3
"""push-with-cache.py — push a rechunked OCI image to ghcr.io with
cross-repo blob mounts.

Per layer:
  1. HEAD destination repo. Skip if blob already exists there.
  2. Otherwise, if cache-plan.json says the blob is mountable from a
     source repo, do a registry-side cross-repo mount (no bytes flow).
  3. Otherwise, upload the blob bytes from the local OCI dir.

Replaces the `skopeo copy oci:dir docker://...` step. Falls back to
upload from local on any mount failure (resilient to cache infra
hiccups). Errors hard if a layer is neither in the OCI dir nor in the
cache plan — that would mean the rechunker handed us an inconsistent
result.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cache_client import GhcrClient  # noqa: E402


def _read_oci_manifest(oci_dir: Path, ref_name: str = "rechunked") -> tuple[dict, dict]:
    """Return (manifest_dict, manifest_descriptor_from_index)."""
    index = json.loads((oci_dir / "index.json").read_text())
    target = None
    for m in index.get("manifests", []):
        ann = m.get("annotations") or {}
        if ann.get("org.opencontainers.image.ref.name") == ref_name:
            target = m
            break
    if target is None:
        # No tag annotation — fall back to first manifest.
        target = index["manifests"][0]
    digest = target["digest"]
    manifest_path = oci_dir / "blobs" / "sha256" / digest.removeprefix("sha256:")
    manifest = json.loads(manifest_path.read_text())
    return manifest, target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="OCI image directory (skopeo `oci:` source)")
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
    manifest, _ = _read_oci_manifest(oci_dir)

    cache_plan_path = oci_dir / "cache-plan.json"
    cache_plan_layers: dict[str, dict] = {}
    if cache_plan_path.exists():
        try:
            cache_plan = json.loads(cache_plan_path.read_text())
            cache_plan_layers = cache_plan.get("layers", {})
        except (OSError, ValueError) as e:
            print(f"WARN: cache-plan.json unreadable: {e}", file=sys.stderr)

    client = GhcrClient.from_authfile(args.auth_file)
    dst_repo = args.dst_repo

    # Stats
    n_skip_exists = 0
    n_mounted = 0
    n_uploaded = 0
    n_mount_fallback = 0
    bytes_uploaded = 0
    bytes_mounted = 0
    bytes_skipped = 0

    layers = manifest.get("layers", [])
    print(f"==> Pushing {len(layers)} layers + 1 config + 1 manifest "
          f"to ghcr.io/{dst_repo}:{args.dst_tag}")

    blobs_dir = oci_dir / "blobs" / "sha256"

    for i, layer in enumerate(layers, 1):
        digest = layer["digest"]
        size = layer["size"]
        local_path = blobs_dir / digest.removeprefix("sha256:")
        plan_entry = cache_plan_layers.get(digest)

        # 1. Already in destination?
        if client.blob_exists(dst_repo, digest):
            n_skip_exists += 1
            bytes_skipped += size
            print(f"  [{i:3d}/{len(layers)}] {digest[:19]}  EXISTS")
            continue

        # 2. Mountable from a cache source repo?
        if plan_entry and plan_entry.get("source"):
            src = plan_entry["source"]
            if client.blob_mount(dst_repo, src, digest):
                n_mounted += 1
                bytes_mounted += size
                print(f"  [{i:3d}/{len(layers)}] {digest[:19]}  MOUNT  from {src}")
                continue
            print(
                f"  [{i:3d}/{len(layers)}] {digest[:19]}  mount failed, "
                f"falling back to download+upload"
            )
            # Fall through to upload path. Need bytes locally; fetch from
            # source repo, then upload to destination.
            tmp_path = local_path
            if not local_path.exists():
                tmp_path = local_path.parent / f".tmp-{digest.removeprefix('sha256:')}"
                if not client.blob_get(src, digest, tmp_path):
                    sys.exit(
                        f"FATAL: layer {digest} not local and cache fetch from "
                        f"{src} failed"
                    )
            ok = client.blob_upload(dst_repo, tmp_path, digest)
            if tmp_path != local_path:
                tmp_path.unlink(missing_ok=True)
            if not ok:
                sys.exit(f"FATAL: blob upload of {digest} failed")
            n_mount_fallback += 1
            bytes_uploaded += size
            continue

        # 3. Upload from local OCI dir.
        if not local_path.exists():
            sys.exit(
                f"FATAL: layer {digest} not in OCI dir and no cache plan entry. "
                f"Rechunker output is inconsistent."
            )
        if not client.blob_upload(dst_repo, local_path, digest):
            sys.exit(f"FATAL: blob upload of {digest} failed")
        n_uploaded += 1
        bytes_uploaded += size
        print(f"  [{i:3d}/{len(layers)}] {digest[:19]}  UPLOAD ({size:,} bytes)")

    # Config blob (always local, always upload if not present)
    config = manifest["config"]
    config_digest = config["digest"]
    config_path = blobs_dir / config_digest.removeprefix("sha256:")
    if not client.blob_exists(dst_repo, config_digest):
        if not client.blob_upload(dst_repo, config_path, config_digest):
            sys.exit(f"FATAL: config blob upload failed")
        print(f"  config {config_digest[:19]}  UPLOAD")
    else:
        print(f"  config {config_digest[:19]}  EXISTS")

    # Manifest PUT
    manifest_path = blobs_dir.parent.parent / "blobs" / "sha256"
    # Read the manifest bytes back from disk so we PUT exactly what was
    # written (preserving JSON ordering/whitespace).
    # The OCI index referenced manifest by digest; find it.
    _, mref = _read_oci_manifest(oci_dir)
    manifest_bytes = (
        manifest_path / mref["digest"].removeprefix("sha256:")
    ).read_bytes()
    media_type = mref.get("mediaType", "application/vnd.oci.image.manifest.v1+json")

    import urllib.parse
    url = (
        f"https://ghcr.io/v2/{dst_repo}/manifests/"
        f"{urllib.parse.quote(args.dst_tag, safe='')}"
    )
    status, _, body = client._request(
        "PUT", url, dst_repo, action="push",
        headers={"Content-Type": media_type, "Content-Length": str(len(manifest_bytes))},
        data=manifest_bytes,
        timeout=60,
    )
    if status != 201:
        sys.exit(f"FATAL: manifest PUT failed {status}: {body!r}")
    print(f"  manifest {mref['digest'][:19]}  PUT  -> :{args.dst_tag}")

    # Summary
    elapsed = time.monotonic() - t_start
    mb = lambda b: f"{b / 1024 / 1024:.1f} MiB"
    print()
    print(f"=== Push complete in {elapsed:.1f}s ===")
    print(f"    {n_skip_exists:3d} layers already in dest ({mb(bytes_skipped)})")
    print(f"    {n_mounted:3d} layers cross-repo mounted ({mb(bytes_mounted)})")
    print(f"    {n_uploaded:3d} layers uploaded fresh ({mb(bytes_uploaded)})")
    if n_mount_fallback:
        print(f"    {n_mount_fallback:3d} layers mount-failed → uploaded "
              f"(network glitch or cache GC)")


if __name__ == "__main__":
    main()
