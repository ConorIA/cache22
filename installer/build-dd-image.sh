#!/usr/bin/env bash
# build-dd-image.sh — produce a prebuilt, flashable cache22 disk image.
#
# Reuses cache22-install's partition/install/deploy functions against a
# loopback file instead of a real disk, then shrinks the result to the
# smallest size that holds the deployment and compresses it. The output
# (cache22-<variant>-bios.raw.zst) is meant to be streamed straight onto
# a VPS disk with the 'reinstall' tool's dd mode (or any raw dd), where a
# baked first-boot service grows it to fill the target disk.
#
# The image always uses the legacy-BIOS GRUB layout (no Secure Boot, no
# UKI, no LUKS) — the configuration that does not depend on per-machine
# key material and so can be baked once and flashed everywhere.
#
# Run as root, in an environment with podman, sgdisk, btrfs-progs,
# e2fsprogs, util-linux and zstd. The bootloader (grub-install) and the
# target userland come from the OCI image itself, not the host.

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

VARIANT="arch-server"
OUTDIR="."
INIT_SIZE="20G"      # generous sparse working size; shrunk at the end
MARGIN_MIB=1024      # free space left in the fs above current usage

usage() {
    cat <<EOF
Usage: $0 [--variant <id>] [--out <dir>] [--init-size <size>] [--margin-mib <n>]

  --variant     cache22 variant id (default: $VARIANT). Server variants only.
  --out         output directory for the .raw.zst (default: $OUTDIR)
  --init-size   sparse working image size before shrink (default: $INIT_SIZE)
  --margin-mib  free space (MiB) kept above current usage (default: $MARGIN_MIB)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)    VARIANT="$2"; shift 2 ;;
        --out)        OUTDIR="$2"; shift 2 ;;
        --init-size)  INIT_SIZE="$2"; shift 2 ;;
        --margin-mib) MARGIN_MIB="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

[[ "$EUID" -eq 0 ]] || { echo "Must run as root." >&2; exit 1; }
case "$VARIANT" in
    *server) ;;
    *) echo "build-dd-image only supports server variants (got '$VARIANT')." >&2; exit 1 ;;
esac

# cache22-install's grub chroot does `mount --rbind /sys` then a recursive
# umount. With /sys shared (the usual default) that umount propagates to
# peers and can tear down the host's own /sys/fs/cgroup, breaking the
# container runtime for the rest of the session. Mark /sys rslave so the
# chroot's umount cannot reach the host. Harmless in a disposable CI
# runner; important when building on a real machine.
mount --make-rslave /sys 2>/dev/null || true

IMAGE="ghcr.io/cmspam/cache22-${VARIANT}:rolling"
RAW="$(readlink -f "$OUTDIR")/cache22-${VARIANT}-bios.raw"

# Reuse the installer's functions without running its interactive main().
NO_PROMPT=1
# shellcheck source=cache22-install
source "$HERE/cache22-install"
# cache22-install's functions are written WITHOUT errexit: they return
# nonzero in normal operation (empty greps, idempotent unmounts) and call
# die() for real failures. Match that contract; our own steps below guard
# themselves explicitly with run().
set +e

# Abort the build if a critical step fails (installer functions die() on
# their own; this covers our own commands).
run() { "$@" || die "build step failed: $*"; }

# Force the legacy-BIOS path regardless of the build host's firmware: CI
# runners are UEFI VMs, but the flashed image must be BIOS-bootable and
# carry no Secure Boot / UKI machinery.
is_uefi() { return 1; }

CFG[image]="$IMAGE"
CFG[mode]="auto"
CFG[scratch_part]="tmpfs"     # build hosts have ample RAM
CFG[filesystem]="btrfs"
CFG[username]="cache"
CFG[fullname]="cache22"
CFG[password]="cache"
CFG[hostname]="cache22"
CFG[reboot]="no"

LOOP=""
cleanup() {
    set +e
    teardown_target 2>/dev/null
    [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null
}
trap cleanup EXIT

echo "==> Building DD image for $VARIANT from $IMAGE"
mkdir -p "$(dirname "$RAW")"
rm -f "$RAW" "$RAW.zst"
run truncate -s "$INIT_SIZE" "$RAW"
LOOP="$(losetup --find --show --partscan "$RAW")" || die "losetup failed"
[[ -b "$LOOP" ]] || die "no loop device"
CFG[disk]="$LOOP"
echo "==> Working image $RAW on $LOOP"

# Lay the system down using the real installer's code path.
decide_auto_scratch
partition_auto
setup_scratch
setup_target
run_bootc_install
configure_deploy
install_grub_bios

# ── DD-only finalisation, injected straight into the deployment ──────────
DEPLOY_ETC="$(deploy_etc)"
echo "==> Applying DD-image finalisation in $DEPLOY_ETC"

# 1. Harden sshd: the public default password 'cache' must only work on
#    the provider console, never over the network.
install -d -m 0755 "$DEPLOY_ETC/ssh/sshd_config.d"
cat > "$DEPLOY_ETC/ssh/sshd_config.d/10-cache22-dd.conf" <<'EOF'
# cache22 DD image: the default 'cache' password is public, so it must
# never be usable over the network. Add your own user + key, then relax
# these if you really want password SSH.
PasswordAuthentication no
PermitRootLogin no
KbdInteractiveAuthentication no
EOF

# 2. Force a password change at the first console login (shadow field 3,
#    days-since-epoch of last change, set to 0 = expired).
sed -i -E 's/^(cache:[^:]*):[0-9]+:/\1:0:/' "$DEPLOY_ETC/shadow"

# 2b. Auto-enable password SSH once the default password is changed. The
#     public 'cache' password is never reachable over the network, so a
#     change can only happen on the console or via a keyed sudo session;
#     that change is therefore proof the new password is locally chosen
#     and safe to expose. A path unit watches /etc/shadow; the service
#     also runs once per boot to reconcile. This gives plain-flash users
#     SSH access without hand-editing sshd_config.
install -d -m 0755 "$DEPLOY_ETC/cache22" \
    "$DEPLOY_ETC/systemd/system/multi-user.target.wants"
cat > "$DEPLOY_ETC/cache22/ssh-unlock.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Field 3 of /etc/shadow is the days-since-epoch of the last password
# change. The DD image bakes it as 0 (expired). A non-zero value means
# the default 'cache' password has been replaced.
lastchange="$(getent shadow cache | cut -d: -f3)"
[[ -n "$lastchange" && "$lastchange" != "0" ]] || exit 0
cat > /etc/ssh/sshd_config.d/10-cache22-dd.conf <<'CONF'
# Default password has been changed; password SSH is now enabled.
# Root login stays disabled; use the 'cache' user (wheel/sudo).
PasswordAuthentication yes
PermitRootLogin no
CONF
systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || true
systemctl disable cache22-ssh-unlock.path 2>/dev/null || true
systemctl stop cache22-ssh-unlock.path 2>/dev/null || true
EOF
chmod 0755 "$DEPLOY_ETC/cache22/ssh-unlock.sh"

cat > "$DEPLOY_ETC/systemd/system/cache22-ssh-unlock.service" <<'EOF'
[Unit]
Description=Enable password SSH once the default cache22 password is changed
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash /etc/cache22/ssh-unlock.sh

[Install]
WantedBy=multi-user.target
EOF

cat > "$DEPLOY_ETC/systemd/system/cache22-ssh-unlock.path" <<'EOF'
[Unit]
Description=Watch for a cache22 default-password change to enable password SSH

# Watch both the file (in-place edits) and the directory: passwd replaces
# /etc/shadow via rename, which a file-level watch misses but a directory
# watch catches. The service is idempotent and no-ops until the password
# is actually changed, so extra early-boot triggers are harmless.
[Path]
PathModified=/etc/shadow
PathModified=/etc
Unit=cache22-ssh-unlock.service

[Install]
WantedBy=paths.target
EOF
ln -sfn ../cache22-ssh-unlock.service \
    "$DEPLOY_ETC/systemd/system/multi-user.target.wants/cache22-ssh-unlock.service"
install -d -m 0755 "$DEPLOY_ETC/systemd/system/paths.target.wants"
ln -sfn ../cache22-ssh-unlock.path \
    "$DEPLOY_ETC/systemd/system/paths.target.wants/cache22-ssh-unlock.path"

# 3. First-boot grow: the image is shrunk to minimal, so on first boot it
#    must extend the (last) root partition to fill the flashed disk and
#    grow the btrfs to match. sfdisk + btrfs-progs are always present; no
#    extra packages. The unit deletes its own script so it runs exactly
#    once.
install -d -m 0755 "$DEPLOY_ETC/cache22"
cat > "$DEPLOY_ETC/cache22/firstboot-grow.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Grow the cache22 root partition + btrfs to fill the disk after the
# minimal DD image was flashed onto a larger target.
src="$(findmnt -no SOURCE /)"
src="${src%%[*}"                       # strip any [/subvol] suffix
name="$(basename "$src")"
disk="/dev/$(lsblk -no PKNAME "$src")"
partnum="$(cat "/sys/class/block/$name/partition")"
# Extend the last partition to the end of the disk. sfdisk rewrites both
# GPT headers, fixing the backup header the small image left mid-disk.
echo ', +' | sfdisk -N "$partnum" --no-reread --force "$disk" || true
partprobe "$disk" 2>/dev/null || true
udevadm settle 2>/dev/null || true
btrfs filesystem resize max /
EOF
chmod 0755 "$DEPLOY_ETC/cache22/firstboot-grow.sh"

cat > "$DEPLOY_ETC/systemd/system/cache22-firstboot-grow.service" <<'EOF'
[Unit]
Description=Grow cache22 root filesystem to fill the disk (first boot)
After=local-fs.target
ConditionPathExists=/etc/cache22/firstboot-grow.sh

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash /etc/cache22/firstboot-grow.sh
ExecStartPost=/usr/bin/rm -f /etc/cache22/firstboot-grow.sh

[Install]
WantedBy=multi-user.target
EOF
install -d -m 0755 "$DEPLOY_ETC/systemd/system/multi-user.target.wants"
ln -sfn ../cache22-firstboot-grow.service \
    "$DEPLOY_ETC/systemd/system/multi-user.target.wants/cache22-firstboot-grow.service"

# ── Shrink to the smallest size that holds the deployment ────────────────
teardown_target
ROOT_PART="${CFG[root_part]}"
echo "==> Shrinking $ROOT_PART to fit"
mkdir -p "$TARGET"
run mount -o "subvol=root,$BTRFS_OPTS" "$ROOT_PART" "$TARGET"
used_kib="$(df -k --output=used "$TARGET" | tail -1 | tr -d ' ')"
[[ "$used_kib" =~ ^[0-9]+$ ]] || die "could not read used space"
target_mib=$(( (used_kib + 1023) / 1024 + MARGIN_MIB ))
echo "    used=$(( used_kib / 1024 ))MiB  +margin=${MARGIN_MIB}MiB  → fs target=${target_mib}MiB"
run btrfs filesystem resize "${target_mib}M" "$TARGET"
run umount "$TARGET"

# Resize the root GPT partition (last partition) to the new fs size plus a
# small slack, preserving its start sector, label and type. sgdisk has no
# in-place resize, so delete + recreate at the same start.
part_mib=$(( target_mib + 8 ))
# Root is the last partition; its number is the trailing digits of the
# device path that partition_auto resolved (e.g. /dev/loop0p3 -> 3).
root_pn="${ROOT_PART##*p}"
start_sector="$(sgdisk -i "$root_pn" "$LOOP" | awk -F': ' '/First sector/{print $2}' | awk '{print $1}')"
[[ "$start_sector" =~ ^[0-9]+$ ]] || die "could not read root start sector"
echo "==> Recreating root partition p${root_pn} at sector ${start_sector}, size ${part_mib}MiB"
run sgdisk -d "$root_pn" "$LOOP"
run sgdisk -n "${root_pn}:${start_sector}:+${part_mib}M" -t "${root_pn}:8304" \
    -c "${root_pn}:cache22-root" "$LOOP"
partprobe "$LOOP" || true
udevadm settle || true

# Truncate the file just past the root partition's end, then relocate the
# backup GPT to the new disk end.
end_sector="$(sgdisk -i "$root_pn" "$LOOP" | awk -F': ' '/Last sector/{print $2}' | awk '{print $1}')"
[[ "$end_sector" =~ ^[0-9]+$ ]] || die "could not read root end sector"
losetup -d "$LOOP"; LOOP=""
final_bytes=$(( (end_sector + 34) * 512 ))
run truncate -s "$final_bytes" "$RAW"
LOOP="$(losetup --find --show --partscan "$RAW")" || die "re-losetup failed"
sgdisk -e "$LOOP" >/dev/null 2>&1 || true
sgdisk -v "$LOOP" || true
losetup -d "$LOOP"; LOOP=""

ZSTD_LEVEL="${ZSTD_LEVEL:-19}"
echo "==> Compressing $RAW ($(du -h "$RAW" | cut -f1)) → ${RAW}.zst (zstd -${ZSTD_LEVEL})"
zstd "-${ZSTD_LEVEL}" -T0 --rm -f "$RAW" -o "${RAW}.zst"
echo "==> Done: ${RAW}.zst ($(du -h "${RAW}.zst" | cut -f1))"
