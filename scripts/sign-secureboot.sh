#!/usr/bin/env bash
# Sign every installed kernel's vmlinuz with the cache22 SB key. shim
# loads grub via Fedora's vendor cert; grub's shim_lock verifier then
# asks shim to verify the kernel against MOK. We enroll the cache22
# cert into MOK at install time, so shim trusts our kernel signatures.
#
# Sign vmlinuz directly with `sbsign` — no objcopy, no SBAT injection.
# Per shim's SBAT.md, kernels don't carry SBAT (only chainloaded EFI
# binaries: shim/grub/systemd-boot do). Per Bazzite/Arch wiki/Gentoo,
# `sbsign vmlinuz vmlinuz` on the dual-format bzImage is the correct
# approach.
#
# Skipped on fork-PR builds (no key); the unsigned kernel still boots
# with SB off, which is fine for those builds.

set -euo pipefail

KEY=/run/secrets/sbkey
CERT=/usr/share/cache22/secureboot.crt

if [[ ! -s "$KEY" ]]; then
    echo "==> No SB key at $KEY — skipping kernel signing (build will be unsigned)"
    exit 0
fi
[[ -f "$CERT" ]] || { echo "ERROR: $CERT missing (system_files overlay incomplete?)" >&2; exit 1; }

shopt -s nullglob
signed=0
for kver_dir in /usr/lib/modules/*/; do
    kver="$(basename "$kver_dir")"
    vmlinuz="${kver_dir}vmlinuz"
    if [[ ! -f "$vmlinuz" ]]; then
        echo "    skipping $kver (no vmlinuz)"
        continue
    fi

    # Idempotent for partial rebuilds.
    if sbverify --list "$vmlinuz" 2>&1 | grep -q 'image signature issuers'; then
        echo "    $kver: already signed, skipping"
        continue
    fi

    echo "==> $kver: sbsigning vmlinuz"
    # faketime pins sbsign's PE-signature signing time so the resulting
    # vmlinuz is byte-stable across rebuilds. Without this, sbsign reads
    # wall-clock and the kernel-modules layer (~200 MiB) drifts every
    # build even when the kernel itself didn't change.
    faketime "@${SOURCE_DATE_EPOCH:-0}" \
        sbsign --key "$KEY" --cert "$CERT" \
               --output "${vmlinuz}.signed" "$vmlinuz"
    mv "${vmlinuz}.signed" "$vmlinuz"
    echo "    $kver: $(stat -c%s "$vmlinuz") bytes signed"
    # `((signed++))` returns the pre-increment value as exit status, which
    # is 0 on the first iteration → `set -e` kills the script. Use the
    # arithmetic-assignment form which always exits 0.
    signed=$((signed + 1))
done

if (( signed == 0 )); then
    echo "==> No unsigned kernels found"
fi
echo "==> Kernel signing complete"
