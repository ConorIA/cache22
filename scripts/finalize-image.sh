#!/usr/bin/env bash
# Final image cleanup + branding. Runs after pacman + initramfs, before
# bootc lint. See docs/IMAGE_BUILD.md for the full pipeline.

set -euo pipefail

# cachyos-hooks ships a plymouth/mkinitcpio hook that errors under dracut.
echo "==> Removing mkinitcpio-tied alpm hook from cachyos-hooks"
rm -f /usr/share/libalpm/hooks/90-plymouth-initramfs.hook

echo "==> Generating locales (per /etc/locale.gen)"
locale-gen 2>&1 | tail -5

echo "==> Rewriting /etc/os-release + /etc/lsb-release with cache22 identity"
VARIANT="${VARIANT:-cachy-kde}"
case "$VARIANT" in
    cachy-kde)    VARIANT_PRETTY="CachyOS-based KDE" ;;
    cachy-server) VARIANT_PRETTY="CachyOS-based Server" ;;
    arch-kde)     VARIANT_PRETTY="Arch-based KDE" ;;
    arch-server)  VARIANT_PRETTY="Arch-based Server" ;;
    *)            VARIANT_PRETTY="$VARIANT" ;;
esac
case "$VARIANT" in
    cachy-*) ID_LIKE_LINE='ID_LIKE="cachyos arch"' ;;
    *)       ID_LIKE_LINE='ID_LIKE="arch"' ;;
esac
for f in /etc/os-release /usr/lib/os-release; do
    [[ -f "$f" ]] || continue
    cat > "$f" <<EOF
NAME="cache22"
PRETTY_NAME="cache22 (${VARIANT_PRETTY})"
ID=cache22
${ID_LIKE_LINE}
BUILD_ID="rolling"
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/cmspam/cache22"
DOCUMENTATION_URL="https://github.com/cmspam/cache22/tree/main/docs"
SUPPORT_URL="https://github.com/cmspam/cache22/issues"
BUG_REPORT_URL="https://github.com/cmspam/cache22/issues"
LOGO=cache22
VARIANT="${VARIANT_PRETTY}"
VARIANT_ID=${VARIANT}
EOF
done
cat > /etc/lsb-release <<EOF
DISTRIB_ID=cache22
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="cache22 (${VARIANT_PRETTY})"
EOF

# ostree expects per-stateroot /var; redirect the standard top-level
# user-writable dirs to /var/<name> so they survive across the
# read-only /usr composefs.
#   /home → /var/home          user homes (already standard)
#   /srv  → /var/srv           service-specific data
#   /root → /var/roothome      root's home
#   /usr/local → /var/usrlocal scripts/binaries dropped into /usr/local/bin
#                              (already in default PATH) without needing
#                              bootc usroverlay
#   /opt  → /var/opt           third-party apps (chrome, discord, anaconda,
#                              etc.) that install themselves under /opt
# Same pattern Fedora Silverblue / Atomic Desktops use. Must run after
# all pacman ops.
echo "==> Replacing /home, /srv, /root, /usr/local, /opt with → var symlinks"
rm -rf /home /srv /root /usr/local /opt
ln -s var/home          /home
ln -s var/srv           /srv
ln -s var/roothome      /root
ln -s ../var/usrlocal   /usr/local
ln -s var/opt           /opt

# bootc/ostree look for /ostree at /. Arch's filesystem package doesn't
# ship the symlink Fedora's does.
echo "==> Adding /ostree → sysroot/ostree symlink"
rm -rf /ostree
ln -s sysroot/ostree /ostree

# bootc-container-lint baseimage-root requires /sysroot to exist.
echo "==> Creating /sysroot mount point"
mkdir -p /sysroot
chmod 0755 /sysroot

# cockpit's /etc/issue.d/cockpit.issue → /run/cockpit/issue prints an
# "Activate the web console with..." line at every login. We want it gone.
if [[ -L /etc/issue.d/cockpit.issue || -f /etc/issue.d/cockpit.issue ]]; then
    echo "==> Suppressing cockpit's login-banner issue file"
    rm -f /etc/issue.d/cockpit.issue
    : > /etc/issue.d/cockpit.issue
fi

# bootc-container-lint nonempty-boot: /boot must be empty in the image;
# ostree populates it from /usr/lib/modules/<kver>/ at deploy.
echo "==> Removing kernel + microcode from /boot"
rm -f /boot/vmlinuz-*       \
      /boot/initramfs-*.img \
      /boot/intel-ucode.img \
      /boot/amd-ucode.img

# rechunker walks files-only — empty dirs vanish unless re-created via
# extra_dirs. Avahi refuses to start without /etc/avahi/services.
echo "==> Creating empty config dirs that ship empty in upstream packages"
mkdir -p /etc/avahi/services

echo "==> Adding Flathub remote"
flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo || true

echo "==> Enabling systemd presets"
systemctl preset-all --preset-mode=enable-only || true

echo "==> Cleaning pacman cache"
rm -rf /usr/lib/sysimage/pacman/pkg/*

# Volatile/regenerable pacman files. Each is a multi-MiB layer cost
# every build because their bytes drift even when the package set is
# unchanged.
#   sync/*.db    — mirror snapshot; useless on an immutable image
#   pacman.log   — install timestamps; never read at runtime
#   gnupg/*      — pacman's GPG keyring + trustdb. Used only at install
#                  time, which doesn't happen on an immutable image.
#                  trustdb.gpg in particular embeds wall-clock created/
#                  nextcheck epochs that drift every build. The local/
#                  pacman db (which `pacman -Q` and changelog gen need)
#                  lives elsewhere and is preserved.
# If a recovery workflow ever needs to install packages, run
# `pacman-key --init && pacman-key --populate` to rebuild gnupg/.
echo "==> Stripping volatile pacman state"
# Whole sync/ directory: mirror snapshots (.db, .files) and their
# detached signatures (.db.sig). All useless on an immutable image
# and all drift every build because mirror metadata changes.
rm -rf /usr/lib/sysimage/pacman/sync
rm -f  /usr/lib/sysimage/pacman/pacman.log
rm -rf /usr/lib/sysimage/pacman/gnupg

# DKMS now signs modules with the cache22 SB key (see /etc/dkms/
# framework.conf). The default per-build mok.key/pub generated by the
# dkms package is unused — strip it so it doesn't ship in the image.
echo "==> Removing unused DKMS mok keypair"
rm -f /var/lib/dkms/mok.key /var/lib/dkms/mok.pub

# DKMS make.log files capture build-time stdout/stderr with timestamps
# embedded throughout. Not read at runtime, drift every build.
echo "==> Removing DKMS build logs"
find /var/lib/dkms -name make.log -delete 2>/dev/null || true

# /usr/lib/.build-id is a directory of symlinks indexed by binary
# build-IDs. Every binary rebuild changes its build-ID, so this
# directory dirties on every package upgrade — and it's rebuildable
# from the binaries themselves, no runtime use. UBlue's rechunker
# strips it for the same reason.
echo "==> Stripping /usr/lib/.build-id (regenerable, churn-prone)"
[[ -d /usr/lib/.build-id ]] && {
    du -sh /usr/lib/.build-id 2>/dev/null
    rm -rf /usr/lib/.build-id
}

# Arch's setcap-via-alpm-hook needs CAP_SETFCAP (which the build
# container drops); composefs strips security.capability xattrs at
# unpack anyway. SUID is the mode bit composefs preserves, so use it
# for the binaries that need privilege escalation.
echo "==> Setting SUID on binaries that need privilege escalation"
chmod u+s /usr/bin/newuidmap
chmod u+s /usr/bin/newgidmap
chmod u+s /usr/bin/ping
[[ -x /usr/bin/arping ]]    && chmod u+s /usr/bin/arping
[[ -x /usr/bin/clockdiff ]] && chmod u+s /usr/bin/clockdiff
[[ -x /usr/bin/tracepath ]] && chmod u+s /usr/bin/tracepath
echo "==> SUID applied:"
ls -la /usr/bin/newuidmap /usr/bin/newgidmap /usr/bin/ping 2>&1

echo "==> Removing machine-id (regenerated on first boot per machine)"
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# bootc-container-lint var-tmpfiles: anything shipped in /var must be
# recreated by tmpfiles.d on first boot.
echo "==> Converting /var to /usr/share/factory + tmpfiles.d"
/tmp/cache22-build/scripts/var-to-tmpfiles.sh

# bootc-container-lint nonempty-run-tmp. Preserve cache22-build/ for
# remaining Containerfile RUN steps; the final step rm's it anyway.
echo "==> Cleaning /tmp, /var/tmp, /run"
find /tmp     -mindepth 1 -maxdepth 1 ! -name cache22-build -exec rm -rf {} + 2>/dev/null || true
find /var/tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
find /run     -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

echo "==> Image finalization complete"
