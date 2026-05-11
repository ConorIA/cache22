#!/usr/bin/env bash
# Multi-stage AUR fallback. Run inside the aur-builder Containerfile
# stage. Auto-detects packages mentioned in cache22 lists that no
# configured pacman repo provides, then builds them (and any AUR
# transitive deps) into /aur-out plus a local pacman repo db. The main
# Containerfile stage COPYs /aur-out and exposes it as [cache22-aur].
#
# Avoids paru/yay because their pre-built binaries link against a
# specific libalpm soname (drifts with rolling pacman), and source-
# building either one drags in their own toolchain dance. We just
# clone the AUR repo, parse .SRCINFO for deps, and recurse.
#
# usage:
#   build-aur-packages.sh --family cachy \
#                         --manifest packages/manifests/cachy-kde.manifest \
#                         --layers-dir packages/layers/cachy

set -euo pipefail

FAMILY=""
MANIFEST=""
LAYERS_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --family)     FAMILY="$2"; shift 2 ;;
        --manifest)   MANIFEST="$2"; shift 2 ;;
        --layers-dir) LAYERS_DIR="$2"; shift 2 ;;
        *) echo "build-aur-packages.sh: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[[ -n "$FAMILY"     ]] || { echo "build-aur-packages.sh: --family required" >&2; exit 2; }
[[ -n "$MANIFEST"   ]] || { echo "build-aur-packages.sh: --manifest required" >&2; exit 2; }
[[ -n "$LAYERS_DIR" ]] || { echo "build-aur-packages.sh: --layers-dir required" >&2; exit 2; }

OUT=/aur-out
mkdir -p "$OUT"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKGS=$("$SCRIPT_DIR/expand-manifest.sh" \
            --family "$FAMILY" \
            --manifest "$MANIFEST" \
            --layers-dir "$LAYERS_DIR")

# pacman -Syy retry loop: GitHub Releases occasionally serves a transient
# 404 for repo .db files when a release is being updated server-side. The
# main pacman -S has its own 5-attempt retry; mirror that pattern here.
for attempt in 1 2 3 4 5; do
    echo "==> pacman -Syy attempt $attempt"
    if pacman -Syy --noconfirm; then
        break
    fi
    [[ "$attempt" == "5" ]] && { echo "pacman -Syy failed after 5 attempts" >&2; exit 1; }
    echo "    retrying in 30s..."
    sleep 30
done

MISSING=()
for pkg in $PKGS; do
    # Direct hit (real package or virtual provider)
    pacman -Si "$pkg" >/dev/null 2>&1 && continue
    # Group (pacman -S expands these but -Si doesn't recognise them)
    pacman -Sg "$pkg" 2>/dev/null | grep -q . && continue
    MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
    echo "==> No AUR builds needed."
    exit 0
fi

echo "==> AUR build candidates: ${MISSING[*]}"

pacman -S --noconfirm --needed base-devel git

# makepkg refuses to run as root.
useradd -m builder 2>/dev/null || true
echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
chown -R builder:builder "$OUT"

# x86-64-v3 baseline pin. Two base images to worry about:
#   cachyos/cachyos-v3 ships -march=native + -mtune=native + target-cpu=native
#   (would SIGILL on Intel because GHA runs on EPYC)
#   archlinux:latest ships -march=x86-64 -mtune=generic (generic baseline,
#   not v3 at all)
# Rather than try to sed-rewrite both shapes, we just set the full v3
# flag set in our drop-in. /etc/makepkg.conf.d/*.conf is sourced in
# lexical order — ASCII puts digits BEFORE letters, so a 99- file
# would sort BEFORE cachyos's rust.conf and lose. zzz- sorts after
# any letter-prefixed file, guaranteeing our values win.
mkdir -p /etc/makepkg.conf.d
# Reproducibility: -ffile-prefix-map normalizes embedded source paths
# (without it, /tmp/<pkg>/src/... gets baked into binaries), and
# --build-id=sha1 makes the linker's ID deterministic from input order.
# RUSTFLAGS also gets --remap-path-prefix for the same reason.
cat > /etc/makepkg.conf.d/zzz-cache22-v3.conf <<'EOF'
# Cache22 v3 baseline + reproducibility overrides — zzz-* sorts last.
CFLAGS="-march=x86-64-v3 -mtune=generic -O3 -pipe -fno-plt -fexceptions \
-Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security \
-fstack-clash-protection -fcf-protection \
-fno-omit-frame-pointer -mno-omit-leaf-frame-pointer \
-ffile-prefix-map=/tmp=/build -ffile-prefix-map=/home/builder=/build"
CXXFLAGS="$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"
LDFLAGS="-Wl,-O1 -Wl,--sort-common -Wl,--as-needed -Wl,-z,relro -Wl,-z,now \
-Wl,-z,pack-relative-relocs -Wl,--build-id=sha1"
RUSTFLAGS="-C opt-level=3 -C target-cpu=x86-64-v3 \
--remap-path-prefix=/tmp=/build --remap-path-prefix=/home/builder=/build"
DEBUG_RUSTFLAGS="-C debuginfo=2"
CARGO_BUILD_RUSTFLAGS="$RUSTFLAGS"

# Strip non-determinism from final .pkg.tar.zst: tar entries get fixed
# mtime + sorted ordering. makepkg honors PKGEXT and respects SDE for
# the tarball itself when invoked correctly.
PACKAGER="cache22 <cache22@users.noreply.github.com>"
EOF

# Verify by sourcing the conf chain and checking the effective vars.
echo "==> Effective post-source compiler flags:"
EFF=$(bash -c '
    source /etc/makepkg.conf 2>/dev/null
    for f in /etc/makepkg.conf.d/*.conf; do source "$f" 2>/dev/null; done
    echo "CFLAGS=$CFLAGS"
    echo "CXXFLAGS=$CXXFLAGS"
    echo "RUSTFLAGS=$RUSTFLAGS"
')
echo "$EFF"

if ! grep -q 'CFLAGS=.*-march=x86-64-v3' <<<"$EFF"; then
    echo "ERROR: effective CFLAGS lacks -march=x86-64-v3" >&2
    exit 1
fi
if ! grep -q 'RUSTFLAGS=.*target-cpu=x86-64-v3' <<<"$EFF"; then
    echo "ERROR: effective RUSTFLAGS lacks target-cpu=x86-64-v3" >&2
    exit 1
fi

# rustup toolchain pin (cachyos-v3 ships rustup, not rust). No-op when
# absent. Required for any -git AUR pkg whose prepare() runs cargo.
if command -v rustup >/dev/null 2>&1; then
    echo "==> rustup default stable"
    sudo -u builder rustup default stable
fi

# ─── Recursive AUR builder ────────────────────────────────────────
# build_aur_package <name>
#   1. Clone aur.archlinux.org/<name>.git
#   2. Read .SRCINFO (or generate via makepkg --printsrcinfo)
#   3. For each depend / makedepend not in any configured repo: recurse
#   4. Install previously-built AUR deps from /aur-out via pacman -U
#   5. makepkg -s as builder; copy resulting pkg.tar.zst to /aur-out
#   6. Memoize via /aur-out/.built-<name> so diamond deps build once
build_aur_package() {
    local pkg="$1"
    [[ -f "$OUT/.built-$pkg" ]] && return 0

    # Confirm AUR has this package before cloning. ls-remote is much
    # more reliable than the RPC API in CI (which has occasionally
    # returned partial bodies). An empty result means the AUR repo
    # doesn't exist.
    if ! git ls-remote "https://aur.archlinux.org/$pkg.git" 2>/dev/null | grep -q .; then
        cat >&2 <<EOF
ERROR: '$pkg' is listed in cache22 packages/*.txt but resolves nowhere:
       - not a package or virtual provider in any configured pacman repo
       - not a pacman group
       - not in AUR
       Either fix the spelling, replace with the correct package name,
       or remove it from the cache22 package list.
EOF
        exit 1
    fi

    echo "==> Resolving AUR/$pkg"
    rm -rf "/tmp/$pkg"
    git clone --depth 1 "https://aur.archlinux.org/$pkg.git" "/tmp/$pkg"
    [[ -f "/tmp/$pkg/PKGBUILD" ]] || { echo "AUR/$pkg: no PKGBUILD" >&2; exit 1; }
    chown -R builder:builder "/tmp/$pkg"

    local srcinfo
    if [[ -f "/tmp/$pkg/.SRCINFO" ]]; then
        srcinfo=$(cat "/tmp/$pkg/.SRCINFO")
    else
        srcinfo=$(sudo -u builder bash -c "cd /tmp/$pkg && makepkg --printsrcinfo")
    fi

    # depends and makedepends entries look like "<key> = <value>".
    # Strip version constraints (libfoo>=2.0 → libfoo) and any (arch).
    local deps
    deps=$(echo "$srcinfo" \
        | awk -F' = ' '/^\s*(depends|makedepends|checkdepends) = /{print $2}' \
        | sed -e 's/[<>=].*//' -e 's/:.*//' \
        | sort -u)

    local dep
    for dep in $deps; do
        [[ -z "$dep" ]] && continue
        if pacman -Si "$dep" >/dev/null 2>&1; then
            continue   # in some configured repo, makepkg -s will install
        fi
        # Not in any repo → AUR. Recurse.
        build_aur_package "$dep"
    done

    # Install AUR-built deps so makepkg -s sees them as satisfied.
    if compgen -G "$OUT/*.pkg.tar.zst" >/dev/null; then
        pacman -U --needed --noconfirm "$OUT"/*.pkg.tar.zst 2>/dev/null || true
    fi

    echo "==> Building AUR/$pkg"
    sudo -u builder bash -c "
        set -e
        export CFLAGS='-march=x86-64-v3 -mtune=generic -O3 -pipe'
        export CXXFLAGS=\"\$CFLAGS\"
        export RUSTFLAGS='-C opt-level=3 -C target-cpu=x86-64-v3'
        export CARGO_BUILD_RUSTFLAGS=\"\$RUSTFLAGS\"
        cd /tmp/$pkg
        makepkg --noconfirm --skippgpcheck --noprogressbar -s
    "
    cp /tmp/$pkg/*.pkg.tar.zst "$OUT/"
    touch "$OUT/.built-$pkg"
}

for pkg in "${MISSING[@]}"; do
    build_aur_package "$pkg"
done

# Generate the local pacman repo db.
cd "$OUT"

# Emit the list of pkgnames we built, to be picked up by the rechunker
# and grouped into a single cache22-aur layer (so AUR-built packages
# don't scatter into hash-buckets and inflate per-build delta).
# Strip leading $OUT/.built- prefix to get the bare pkgname.
ls .built-* 2>/dev/null | sed 's/^\.built-//' | sort -u > cache22-aur-pkgs.txt
echo "==> AUR sidecar (cache22-aur-pkgs.txt): $(wc -l < cache22-aur-pkgs.txt) pkgs"

rm -f .built-*
repo-add cache22-aur.db.tar.gz *.pkg.tar.zst
ln -sf cache22-aur.db.tar.gz cache22-aur.db
touch .has-packages

echo "==> /aur-out contents:"
ls -la "$OUT"
