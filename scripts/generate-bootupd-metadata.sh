#!/usr/bin/env bash
# Generate /usr/lib/bootupd/updates/ — the payload tree + EFI.json
# that bootupctl install reads at install time.
#
# We can't use `bootupd generate-update-metadata` because that
# command shells out to `rpm -q` to extract package versions, and
# cache22 is pacman-based (no rpm db). The metadata schema is small
# enough to construct by hand.
#
# Inputs:  /usr/lib/efi/{shim,grub2}/<NVR>/EFI/cache22/{shim,grub,mm}.efi
# Outputs: /usr/lib/bootupd/updates/{EFI/cache22/, EFI/BOOT/, EFI.json}

set -euo pipefail

SHIM_DIR=$(ls -d /usr/lib/efi/shim/*/  | head -1)
GRUB_DIR=$(ls -d /usr/lib/efi/grub2/*/ | head -1)
[[ -d "$SHIM_DIR" ]] || { echo "ERROR: no /usr/lib/efi/shim/<NVR> dir"  >&2; exit 1; }
[[ -d "$GRUB_DIR" ]] || { echo "ERROR: no /usr/lib/efi/grub2/<NVR> dir" >&2; exit 1; }

SHIM_NVR=$(basename "$SHIM_DIR")
GRUB_NVR_RAW=$(basename "$GRUB_DIR")
# Strip RPM epoch ("1:") and dist tag (".fcNN") so the rpm_evr field
# matches what bootupd's generate-update-metadata would have written
# (verified against a real Fedora bootupd run: grub2 → "2.12-56").
GRUB_NVR=$(echo "$GRUB_NVR_RAW" | sed -e 's/^[0-9]*://' -e 's/\.fc[0-9]*$//')

OUT=/usr/lib/bootupd/updates
mkdir -p "$OUT/EFI/cache22" "$OUT/EFI/BOOT"

cp "$SHIM_DIR/EFI/cache22/shimx64.efi"  "$OUT/EFI/cache22/"
cp "$SHIM_DIR/EFI/cache22/mmx64.efi"    "$OUT/EFI/cache22/"
cp "$GRUB_DIR/EFI/cache22/grubx64.efi"  "$OUT/EFI/cache22/"
cp "$SHIM_DIR/EFI/BOOT/BOOTX64.EFI"     "$OUT/EFI/BOOT/"
[[ -f "$SHIM_DIR/EFI/BOOT/fbx64.efi" ]] && cp "$SHIM_DIR/EFI/BOOT/fbx64.efi" "$OUT/EFI/BOOT/"

# bootupd's ContentMetadata (src/model.rs:17). Reproducible via SDE.
TS=$(date -u --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%dT%H:%M:%SZ)

cat > "$OUT/EFI.json" <<EOF
{"timestamp":"$TS","version":"grub2-${GRUB_NVR},shim-${SHIM_NVR}","versions":[{"name":"grub2","rpm_evr":"${GRUB_NVR}"},{"name":"shim","rpm_evr":"${SHIM_NVR}"}]}
EOF

echo "==> bootupd metadata staged"
echo "    shim=$SHIM_NVR grub2=$GRUB_NVR"
ls -l "$OUT/EFI/cache22/" "$OUT/EFI/BOOT/" "$OUT/EFI.json"
