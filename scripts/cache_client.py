"""ghcr.io registry HTTP client for cache22's per-variant pkgcache.

Used by:
  - scripts/rechunk-cache22.py — not directly; the rechunker only deals
    with the local index file. No network calls.
  - scripts/push-with-cache.py — for HEAD-blob-then-upload-if-missing
    against the variant's own ghcr.io repo.

All network errors collapse to soft failures so the build never crashes
on transient ghcr.io blips.
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
        self._token_cache: dict[str, tuple[str, float]] = {}

    @classmethod
    def from_authfile(cls, authfile: str | None = None) -> "GhcrClient":
        path = authfile or os.environ.get(
            "REGISTRY_AUTH_FILE",
            os.path.expanduser("~/.docker/config.json"),
        )
        return cls(_read_auth_file(path))

    def _bearer(self, repo: str, action: str = "pull") -> str | None:
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
            print(f"  registry: token request failed: {e}", file=sys.stderr)
            return None
        except Exception as e:  # noqa: BLE001
            print(
                f"  registry: token request unexpected error: "
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
        timeout: float = 60,
    ) -> tuple[int, dict, bytes | None]:
        """Make an HTTP request with bearer auth.

        All network errors collapse to (0, {}, None) so callers can treat
        push failures as soft (fall back to retry / skopeo / etc.).
        """
        token = self._bearer(repo, action)
        h = {"User-Agent": "cache22-push-with-cache/1"}
        if headers:
            h.update(headers)
        if token:
            h["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(url, method=method, data=data, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                resp_headers = dict(r.headers.items())
                body = r.read() if method != "HEAD" else b""
                return r.status, resp_headers, body
        except urllib.error.HTTPError as e:
            body = e.read() if method != "HEAD" else b""
            return e.code, dict(e.headers.items()), body
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
            print(f"  registry: {method} {url} failed: {e}", file=sys.stderr)
            return 0, {}, None
        except Exception as e:  # noqa: BLE001
            print(
                f"  registry: {method} {url} unexpected error: "
                f"{type(e).__name__}: {e}",
                file=sys.stderr,
            )
            return 0, {}, None

    # ── Public ops ──

    def blob_exists(self, repo: str, digest: str) -> bool:
        url = f"https://ghcr.io/v2/{repo}/blobs/{digest}"
        status, _, _ = self._request("HEAD", url, repo, action="pull", timeout=15)
        return status == 200

    def blob_upload(self, repo: str, blob_path: Path, digest: str) -> bool:
        """POST upload init then PUT bytes. Returns True on 201."""
        url = f"https://ghcr.io/v2/{repo}/blobs/uploads/"
        status, headers, _ = self._request(
            "POST", url, repo, action="push",
            headers={"Content-Length": "0"},
            data=b"",
            timeout=30,
        )
        if status not in (201, 202):
            print(
                f"  registry: blob upload init failed {status} for {repo}",
                file=sys.stderr,
            )
            return False
        location = headers.get("Location") or headers.get("location")
        if not location:
            return False
        if location.startswith("/"):
            location = "https://ghcr.io" + location
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
                f"  registry: blob PUT failed {status} for {repo}@{digest[:19]}",
                file=sys.stderr,
            )
            return False
        return True

    def manifest_put(
        self, repo: str, tag: str, manifest_bytes: bytes, media_type: str
    ) -> bool:
        url = (
            f"https://ghcr.io/v2/{repo}/manifests/"
            f"{urllib.parse.quote(tag, safe='')}"
        )
        status, _, _ = self._request(
            "PUT", url, repo, action="push",
            headers={
                "Content-Type": media_type,
                "Content-Length": str(len(manifest_bytes)),
            },
            data=manifest_bytes,
            timeout=60,
        )
        if status != 201:
            print(
                f"  registry: manifest PUT failed {status} for {repo}:{tag}",
                file=sys.stderr,
            )
            return False
        return True
