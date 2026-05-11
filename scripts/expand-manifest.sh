#!/usr/bin/env bash
# Expand a cache22 variant manifest into a deduplicated package list,
# one per line on stdout.
#
# A manifest file lists one layer name per line; comments (#) and blanks
# are ignored. Each layer name resolves to <layers-dir>/<layer>.txt; a
# missing .txt is treated as empty (lets the system_files-only layers
# like kde-gaming exist without a package list).
#
# usage:
#   expand-manifest.sh --family cachy \
#                      --manifest packages/manifests/cachy-kde.manifest \
#                      --layers-dir packages/layers/cachy

set -euo pipefail

FAMILY=""
MANIFEST=""
LAYERS_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --family)     FAMILY="$2"; shift 2 ;;
        --manifest)   MANIFEST="$2"; shift 2 ;;
        --layers-dir) LAYERS_DIR="$2"; shift 2 ;;
        *) echo "expand-manifest.sh: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[[ -n "$FAMILY"     ]] || { echo "expand-manifest.sh: --family required" >&2; exit 2; }
[[ -n "$MANIFEST"   ]] || { echo "expand-manifest.sh: --manifest required" >&2; exit 2; }
[[ -n "$LAYERS_DIR" ]] || { echo "expand-manifest.sh: --layers-dir required" >&2; exit 2; }
[[ -f "$MANIFEST"   ]] || { echo "expand-manifest.sh: manifest not found: $MANIFEST" >&2; exit 1; }
[[ -d "$LAYERS_DIR" ]] || { echo "expand-manifest.sh: layers dir not found: $LAYERS_DIR" >&2; exit 1; }

LAYERS=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$MANIFEST")

FILES=()
for layer in $LAYERS; do
    f="$LAYERS_DIR/$layer.txt"
    if [[ -f "$f" ]]; then
        FILES+=("$f")
    fi
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    exit 0
fi

sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "${FILES[@]}" | sort -u
