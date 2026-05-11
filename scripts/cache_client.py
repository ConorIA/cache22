"""Tiny ghcr.io client for cache22's per-layer blob cache.

Each cached layer is stored as a single-layer OCI image in a dedicated
cache repo (e.g. ghcr.io/cmspam/cache22-pkgcache), tagged by the cache
key. Lookup is `HEAD /v2/<repo>/manifests/<tag>` — the tag IS the index.

Auth uses the docker-login auth file (Basic auth → bearer token via the
standard Docker Registry v2 challenge flow).
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path


# ─── Auth ─────────────────────────────────────────────────────────────────


def _read_auth_file(path: str) -> str | None:
    """Return the base64 'auth' string for ghcr.io from a docker config.json."""
    try:
        cfg = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    auths = cfg.get("auths", {}) or {}
    for host in ("ghcr.io", "https://ghcr.io"):
        entry = auths.get(host)
        if entry and entry.get("auth"):
            return entry["auth"]
    return None


class GhcrClient:
    """Minimal ghcr.io client. Bearer token cached per repo+scope."""

    def __init__(self, auth_b64: str | None):
        self.auth_b64 = auth_b64
        self._token_cache: dict[str, tuple[str, float]] = {}  # scope → (token, expiry)

    @classmethod
    def from_authfile(cls, authfile: str | None = None) -> "GhcrClient":
        path = authfile or os.environ.get(
            "REGISTRY_AUTH_FILE",
            os.path.expanduser("~/.docker/config.json"),
        )
        return cls(_read_auth_file(path))

    # ── Token bearer flow ──

    def _bearer(self, repo: str, action: str = "pull") -> str | None:
        """Get a bearer token for ghcr.io/<repo> with given action(s)."""
        scope = f"repository:{repo}:{action}"
        cached = self._token_cache.get(scope)
        if cached and cached[1] > time.time() + 30:
            return cached[0]
        url = (
            "https://ghcr.io/token?service=ghcr.io&scope="
            + urllib.parse.quote(scope, safe="")
        )
        req = urllib.request.Request(url)
        if self.auth_b64:
            req.add_header("Authorization", f"Basic {self.auth_b64}")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                body = json.loads(r.read())
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            print(f"  cache: token request failed: {e}", file=sys.stderr)
            return None
        except Exception as e:  # noqa: BLE001
            print(
                f"  cache: token request unexpected error: "
                f"{type(e).__name__}: {e}",
                file=sys.stderr,
            )
            return None
        token = body.get("token") or body.get("access_token")
        if not token:
            return None
        self._token_cache[scope] = (token, time.time() + body.get("expires_in", 300))
        return token

    def _request(
        self,
        method: str,
        url: str,
        repo: str,
        action: str = "pull",
        headers: dict | None = None,
        data: bytes | None = None,
        stream_to: Path | None = None,
        timeout: float = 60,
    ) -> tuple[int, dict, bytes | None]:
        """Make an HTTP request with bearer auth. Returns (status, headers, body).

        All network errors (timeouts, connection failures, SSL hiccups,
        URL errors) collapse to (0, {}, None) so the caller can treat the
        cache as a pure optimization layer — any failure falls through to
        the "no cache" path without aborting the build.
        """
        token = self._bearer(repo, action)
        h = {"User-Agent": "cache22-rechunk/1"}
        if headers:
            h.update(headers)
        if token:
            h["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, method=method, data=data, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                resp_headers = dict(r.headers.items())
                if stream_to is not None:
                    with stream_to.open("wb") as out:
                        while True:
                            chunk = r.read(65536)
                            if not chunk:
                                break
                            out.write(chunk)
                    return r.status, resp_headers, None
                body = r.read() if method != "HEAD" else b""
                return r.status, resp_headers, body
        except urllib.error.HTTPError as e:
            body = e.read() if method != "HEAD" else b""
            return e.code, dict(e.headers.items()), body
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            # OSError catches socket.timeout/socket.gaierror;
            # TimeoutError catches builtin read-timeouts on 3.10+;
            # ValueError catches malformed responses.
            print(f"  cache: {method} {url} failed: {e}", file=sys.stderr)
            return 0, {}, None
        except Exception as e:  # noqa: BLE001
            # Last-line safety net: anything we didn't anticipate should
            # still be a soft fail, not a hard rechunker crash.
            print(
                f"  cache: {method} {url} unexpected error: "
                f"{type(e).__name__}: {e}",
                file=sys.stderr,
            )
            return 0, {}, None

    # ── Public ops ──

    def manifest_exists(self, repo: str, tag: str) -> bool:
        """HEAD /v2/<repo>/manifests/<tag>."""
        url = f"https://ghcr.io/v2/{repo}/manifests/{urllib.parse.quote(tag, safe='')}"
        status, _, _ = self._request(
            "HEAD", url, repo, action="pull",
            headers={
                "Accept": "application/vnd.oci.image.manifest.v1+json,"
                          "application/vnd.docker.distribution.manifest.v2+json",
            },
            timeout=15,
        )
        return status == 200

    def manifest_get(self, repo: str, tag: str) -> dict | None:
        """GET /v2/<repo>/manifests/<tag>. Tight timeout — this runs per
        package and is on the critical path for build wall-clock."""
        url = f"https://ghcr.io/v2/{repo}/manifests/{urllib.parse.quote(tag, safe='')}"
        status, _, body = self._request(
            "GET", url, repo, action="pull",
            headers={
                "Accept": "application/vnd.oci.image.manifest.v1+json,"
                          "application/vnd.docker.distribution.manifest.v2+json",
            },
            timeout=10,
        )
        if status != 200 or body is None:
            return None
        try:
            return json.loads(body)
        except ValueError:
            return None

    def blob_get(self, repo: str, digest: str, dst: Path, timeout: float = 600) -> bool:
        """Download blob to dst. Returns True on 200."""
        url = f"https://ghcr.io/v2/{repo}/blobs/{digest}"
        status, _, _ = self._request(
            "GET", url, repo, action="pull", stream_to=dst, timeout=timeout
        )
        return status == 200

    def blob_exists(self, repo: str, digest: str) -> bool:
        url = f"https://ghcr.io/v2/{repo}/blobs/{digest}"
        status, _, _ = self._request(
            "HEAD", url, repo, action="pull", timeout=15
        )
        return status == 200

    def blob_mount(self, target_repo: str, source_repo: str, digest: str) -> bool:
        """Cross-repo mount: tell ghcr.io to make `digest` available in
        `target_repo` by reference to `source_repo`, without transferring
        bytes. Returns True on 201 (Created)."""
        url = (
            f"https://ghcr.io/v2/{target_repo}/blobs/uploads/"
            f"?mount={urllib.parse.quote(digest, safe='')}"
            f"&from={urllib.parse.quote(source_repo, safe='')}"
        )
        # Mount needs push scope on target. Source-repo read access is
        # implicit (the registry validates we have it server-side).
        status, _, _ = self._request(
            "POST", url, target_repo, action="push",
            headers={"Content-Length": "0"},
            data=b"",
            timeout=30,
        )
        # 201 → mounted. 202 → registry chose to start a new upload
        # (mount declined; usually a permission issue or cross-host repo).
        # Treat 202 as a soft fail so the caller can fall back to upload.
        return status == 201

    def blob_upload(self, repo: str, blob_path: Path, digest: str) -> bool:
        """POST then PUT a blob to <repo>. Returns True on 201."""
        # 1. Initiate upload
        url = f"https://ghcr.io/v2/{repo}/blobs/uploads/"
        status, headers, _ = self._request(
            "POST", url, repo, action="push",
            headers={"Content-Length": "0"},
            data=b"",
            timeout=30,
        )
        if status not in (201, 202):
            print(
                f"  cache: blob upload init failed {status}: {url}",
                file=sys.stderr,
            )
            return False
        location = headers.get("Location") or headers.get("location")
        if not location:
            return False
        if location.startswith("/"):
            location = "https://ghcr.io" + location
        # 2. Append digest as query param and PUT the bytes
        sep = "&" if "?" in location else "?"
        put_url = f"{location}{sep}digest={urllib.parse.quote(digest, safe='')}"
        size = blob_path.stat().st_size
        with blob_path.open("rb") as f:
            data = f.read()
        status, _, _ = self._request(
            "PUT", put_url, repo, action="push",
            headers={
                "Content-Type": "application/octet-stream",
                "Content-Length": str(size),
            },
            data=data,
            timeout=600,
        )
        if status != 201:
            print(
                f"  cache: blob PUT failed {status}: {put_url}",
                file=sys.stderr,
            )
            return False
        return True

    def push_layer_image(
        self,
        repo: str,
        tag: str,
        layer_blob_path: Path,
        layer_digest: str,
        layer_size: int,
        diff_id: str,
        media_type: str = "application/vnd.oci.image.layer.v1.tar+zstd",
    ) -> bool:
        """Push a single-layer OCI image (layer + minimal config + manifest)
        to <repo> tagged <tag>. Used to populate the cache repo so a future
        lookup finds the (digest, size) of this exact layer."""
        # 1. Upload the layer blob (skip if already exists).
        if not self.blob_exists(repo, layer_digest):
            if not self.blob_upload(repo, layer_blob_path, layer_digest):
                return False

        # 2. Build a tiny config blob.
        config = {
            "architecture": "amd64",
            "os": "linux",
            "rootfs": {"type": "layers", "diff_ids": [diff_id]},
            "config": {},
        }
        config_bytes = json.dumps(config, separators=(",", ":")).encode()
        config_digest = "sha256:" + hashlib.sha256(config_bytes).hexdigest()

        # 3. Upload the config blob (skip if already exists).
        if not self.blob_exists(repo, config_digest):
            # Inline upload via POST?digest= shortcut.
            url = (
                f"https://ghcr.io/v2/{repo}/blobs/uploads/"
                f"?digest={urllib.parse.quote(config_digest, safe='')}"
            )
            status, _, _ = self._request(
                "POST", url, repo, action="push",
                headers={
                    "Content-Type": "application/octet-stream",
                    "Content-Length": str(len(config_bytes)),
                },
                data=config_bytes,
                timeout=30,
            )
            if status != 201:
                # Fall back to two-step.
                config_path = layer_blob_path.parent / f".cfg-{config_digest[7:19]}"
                config_path.write_bytes(config_bytes)
                ok = self.blob_upload(repo, config_path, config_digest)
                config_path.unlink(missing_ok=True)
                if not ok:
                    return False

        # 4. PUT the manifest at the tag. The layer's diff_id is recorded
        #    as an annotation so a cache lookup can recover it without a
        #    separate GET on the config blob.
        manifest = {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": config_digest,
                "size": len(config_bytes),
            },
            "layers": [
                {
                    "mediaType": media_type,
                    "digest": layer_digest,
                    "size": layer_size,
                    "annotations": {"io.cache22.diff_id": diff_id},
                }
            ],
            "annotations": {
                "org.opencontainers.image.title": "cache22 layer cache",
                "io.cache22.diff_id": diff_id,
            },
        }
        manifest_bytes = json.dumps(manifest, separators=(",", ":")).encode()
        url = (
            f"https://ghcr.io/v2/{repo}/manifests/"
            f"{urllib.parse.quote(tag, safe='')}"
        )
        status, _, _ = self._request(
            "PUT", url, repo, action="push",
            headers={
                "Content-Type": "application/vnd.oci.image.manifest.v1+json",
                "Content-Length": str(len(manifest_bytes)),
            },
            data=manifest_bytes,
            timeout=30,
        )
        if status != 201:
            print(
                f"  cache: manifest PUT failed {status}: {url}",
                file=sys.stderr,
            )
            return False
        return True


# ─── Cache key helpers ────────────────────────────────────────────────────


CACHE_KEY_VERSION = "r1"


def solo_cache_key(pkg_dir_name: str, mtree_path: Path, arch: str = "x86_64") -> str | None:
    """Compute cache key for a solo (per-package) layer.

    Format: solo-<pkg-dir-name>-<arch>-mtree-<sha12>-<rN>

    Returns None if the mtree file is missing (package can't be cached
    without a content fingerprint).
    """
    if not mtree_path.exists():
        return None
    try:
        mtree_bytes = mtree_path.read_bytes()
    except OSError:
        return None
    sha12 = hashlib.sha256(mtree_bytes).hexdigest()[:12]
    return f"solo-{pkg_dir_name}-{arch}-mtree-{sha12}-{CACHE_KEY_VERSION}"
