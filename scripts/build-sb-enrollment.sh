#!/usr/bin/env bash
# Stage the cache22 SB cert in DER form for the installer to use as a
# pending MOK enrollment. The installer runs `mokutil --import` against
# this file; on first reboot, MokManager prompts the user for the
# enrollment password, after which shim trusts the cache22 cert via
# MOK and the cache22-signed kernel boots under SB.
#
# We no longer build PK/KEK/db .auth bundles. The chain has shifted:
#   - shim is signed by Microsoft (already in db) — no enrollment needed
#   - grub2 is signed by Fedora's CA, embedded in shim's vendor_cert —
#     no enrollment needed
#   - kernel is signed by cache22's key — enrolled via MOK at first boot
#
# So the only thing the user has to do is type the MOK password once.

set -euo pipefail

CERT_PEM=/usr/share/cache22/secureboot.crt
OUT_DIR=/usr/share/cache22
mkdir -p "$OUT_DIR"

[[ -f "$CERT_PEM" ]] || { echo "ERROR: $CERT_PEM missing — system_files overlay incomplete?" >&2; exit 1; }

openssl x509 -in "$CERT_PEM" -outform DER -out "$OUT_DIR/secureboot.cer"

echo "==> Staged $OUT_DIR/secureboot.cer for MOK enrollment ($(stat -c%s "$OUT_DIR/secureboot.cer") bytes)"
