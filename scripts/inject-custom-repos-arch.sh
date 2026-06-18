#!/usr/bin/env bash
# Configure pacman repos for the ARCH family. Layers cmspam/* + ALHP +
# LizardByte at the top of pacman.conf above stock Arch core/extra/multilib.
# See docs/IMAGE_BUILD.md.
#
# Independent of the cachy family — sibling script shares zero state.

set -euo pipefail

PACMAN_CONF="/etc/pacman.conf"

echo "==> Stripping archlinux Docker minimization (NoExtract block + restoring [multilib])"
# archlinux:latest appends a second [options] block with NoExtract rules
# (man pages, locales, etc.) and removes [multilib] entirely. We want
# full packages and multilib for steam/wine.
SECOND_OPT_LINE=$(grep -n '^\[options\]' "${PACMAN_CONF}" | sed -n '2{s/:.*//;p;}')
if [[ -n "${SECOND_OPT_LINE}" ]]; then
    head -n "$((SECOND_OPT_LINE - 1))" "${PACMAN_CONF}" > "${PACMAN_CONF}.new"
    mv "${PACMAN_CONF}.new" "${PACMAN_CONF}"
fi

if ! grep -qE '^\[multilib\]' "${PACMAN_CONF}"; then
    cat >> "${PACMAN_CONF}" <<'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
fi

echo "==> Initializing pacman master keyring"
pacman-key --init
pacman-key --populate archlinux

echo "==> Installing ALHP keyring + mirrorlist"
# Source of truth: AUR. We query AUR RPC for the current pkgver of each
# package and download from the upstream URLs the PKGBUILDs use, then
# install the same files the AUR package would install.
#
# alhp-keyring: ALHP packages are signed by a buildbot subkey which is
# in turn signed by the master key. --lsign-key on the master alone
# doesn't transitively trust the buildbot key, so we need the full
# alhp.gpg keyring file (containing both keys) installed and populated.
aur_pkgver() {
    # Don't depend on python3 — the archlinux:latest base doesn't ship
    # it, and we run before pacman -S has installed anything. AUR's
    # type=info response is single-line compact JSON; regex out the
    # first "Version":"..." then strip the -pkgrel suffix.
    local pkg=$1 ver
    ver=$(curl -fsSL "https://aur.archlinux.org/rpc/?v=5&type=info&arg=$pkg" \
        | sed -nE 's/.*"Version":"([^"]+)".*/\1/p' | head -1 | cut -d- -f1)
    [[ -n "$ver" ]] || { echo "ERROR: AUR has no package '$pkg'" >&2; return 1; }
    echo "$ver"
}

ALHP_KEYRING_VER=$(aur_pkgver alhp-keyring)
echo "    alhp-keyring: $ALHP_KEYRING_VER (per AUR)"
curl -fsSLo /tmp/alhp-keyring.tar.gz \
    "https://f.alhp.dev/alhp-keyring/alhp-keyring-${ALHP_KEYRING_VER}.tar.gz"
mkdir -p /tmp/alhp-keyring-extract
tar -xzf /tmp/alhp-keyring.tar.gz -C /tmp/alhp-keyring-extract --strip-components=1
install -Dm644 /tmp/alhp-keyring-extract/alhp.gpg \
    /usr/share/pacman/keyrings/alhp.gpg
install -Dm644 /tmp/alhp-keyring-extract/alhp-trusted \
    /usr/share/pacman/keyrings/alhp-trusted
pacman-key --populate alhp
rm -rf /tmp/alhp-keyring.tar.gz /tmp/alhp-keyring-extract

ALHP_MIRRORLIST_VER=$(aur_pkgver alhp-mirrorlist)
echo "    alhp-mirrorlist: $ALHP_MIRRORLIST_VER (per AUR)"
# curl + tar (consistent with alhp-keyring above) instead of git clone —
# git isn't in archlinux:latest by default and we'd just be pulling it
# in for one shallow clone.
curl -fsSLo /tmp/alhp-mirrorlist.tar.gz \
    "https://somegit.dev/ALHP/alhp-mirrorlist/archive/${ALHP_MIRRORLIST_VER}.tar.gz"
mkdir -p /tmp/alhp-mirrorlist-extract
tar -xzf /tmp/alhp-mirrorlist.tar.gz -C /tmp/alhp-mirrorlist-extract --strip-components=1
mkdir -p /etc/pacman.d
install -Dm644 /tmp/alhp-mirrorlist-extract/mirrorlist /etc/pacman.d/alhp-mirrorlist
rm -rf /tmp/alhp-mirrorlist.tar.gz /tmp/alhp-mirrorlist-extract

echo "==> Injecting cmspam + ALHP + LizardByte repos at top of pacman.conf"
TOP_REPOS=$(cat <<'EOF'

# cmspam/* — highest priority. Unsigned (--skippgpcheck upstream),
# SigLevel = Optional TrustAll required.

[bootc-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/bootc-v3/releases/download/latest-v3

[qemu-patched-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/qemu-patched/releases/download/latest-v3

[xe-virt-host-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/xe-virt-repo/releases/download/latest-host

[gamescope-patched-v3]
SigLevel = Optional TrustAll
Server = https://github.com/cmspam/gamescope-patched/releases/download/latest-v3

# Sunshine (game streaming server, Moonlight-compatible) — official
# pacman repo from upstream LizardByte.
[lizardbyte]
SigLevel = Optional TrustAll
Server = https://github.com/LizardByte/pacman-repo/releases/download/stable

# ALHP x86-64-v3 rebuilds. Pacman walks top-to-bottom, so ALHP wins
# wherever a package exists in both ALHP and stock Arch.

[core-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist

[extra-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist

[multilib-x86-64-v3]
Include = /etc/pacman.d/alhp-mirrorlist

EOF
)

awk -v block="${TOP_REPOS}" '
    BEGIN { injected = 0 }
    /^\[(core|extra|multilib)\]/ && !injected {
        print block
        injected = 1
    }
    { print }
' "${PACMAN_CONF}" > "${PACMAN_CONF}.new" \
    && mv "${PACMAN_CONF}.new" "${PACMAN_CONF}"

echo "==> Final pacman.conf [...] section order:"
grep -E '^\[' "${PACMAN_CONF}"
