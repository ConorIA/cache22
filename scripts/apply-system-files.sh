#!/usr/bin/env bash
# Apply cache22 system_files overlays to a target root.
#
# Copies <common-dir>/. then, for each layer named in the manifest,
# <layers-dir>/<layer>/. into <root>. Later layers override earlier ones
# (cp --remove-destination). A missing layer dir is simply skipped, so
# package-only layers (e.g. base, server) need no system_files dir.
#
# usage:
#   apply-system-files.sh --family cachy \
#                         --manifest packages/manifests/cachy-kde.manifest \
#                         --common-dir system_files/common \
#                         --layers-dir system_files/layers/cachy \
#                         --root /

set -euo pipefail

FAMILY=""
MANIFEST=""
COMMON_DIR=""
LAYERS_DIR=""
ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --family)     FAMILY="$2"; shift 2 ;;
        --manifest)   MANIFEST="$2"; shift 2 ;;
        --common-dir) COMMON_DIR="$2"; shift 2 ;;
        --layers-dir) LAYERS_DIR="$2"; shift 2 ;;
        --root)       ROOT="$2"; shift 2 ;;
        *) echo "apply-system-files.sh: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[[ -n "$FAMILY"     ]] || { echo "apply-system-files.sh: --family required" >&2; exit 2; }
[[ -n "$MANIFEST"   ]] || { echo "apply-system-files.sh: --manifest required" >&2; exit 2; }
[[ -n "$COMMON_DIR" ]] || { echo "apply-system-files.sh: --common-dir required" >&2; exit 2; }
[[ -n "$LAYERS_DIR" ]] || { echo "apply-system-files.sh: --layers-dir required" >&2; exit 2; }
[[ -n "$ROOT"       ]] || { echo "apply-system-files.sh: --root required" >&2; exit 2; }
[[ -f "$MANIFEST"   ]] || { echo "apply-system-files.sh: manifest not found: $MANIFEST" >&2; exit 1; }

if [[ -d "$COMMON_DIR" ]]; then
    echo "==> Overlay: common"
    cp -av --remove-destination "$COMMON_DIR/." "$ROOT"
fi

LAYERS=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$MANIFEST")

for layer in $LAYERS; do
    d="$LAYERS_DIR/$layer"
    if [[ -d "$d" ]]; then
        echo "==> Overlay: $layer"
        cp -av --remove-destination "$d/." "$ROOT"
    fi
done
