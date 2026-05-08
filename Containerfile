# cache22 image build. See docs/IMAGE_BUILD.md.
#
# Build args: VARIANT_FAMILY (cachy|arch), VARIANT_TYPE (kde|server),
# VARIANT (e.g. arch-kde). CI passes all three.

ARG BASE_IMAGE=docker.io/cachyos/cachyos-v3
ARG BASE_TAG=latest

# ─── Reproducibility env (applied to BOTH stages) ────────────────
# SOURCE_DATE_EPOCH = git commit timestamp passed by the CI workflow.
# - dracut --reproducible uses this for cpio mtimes (initramfs becomes
#   content-stable for same input modules)
# - kbuild uses it as __DATE__/__TIME__ replacement in DKMS module compiles
# - many other tools (gzip, ar, etc.) honor it for archive entry mtimes
# - KBUILD_BUILD_USER/HOST are baked into Linux module utsname strings
#   if not set explicitly; pinning eliminates that source of variance
ARG SOURCE_DATE_EPOCH=0

# ─── Stage 0: fedora-bootloader ───────────────────────────────────
# Pull Fedora's MS-signed shim + Fedora-CA-signed grub2 from the
# current stable Fedora release. dnf handles version resolution,
# dependencies, and GPG verification — no URL hardcoding. The vendor
# subdir gets renamed from EFI/fedora to EFI/cache22 so bootupd's
# auto-detection picks "cache22" as our vendor at runtime.
FROM registry.fedoraproject.org/fedora:latest AS fedora-bootloader
RUN dnf install -y \
        --setopt=install_weak_deps=False \
        --setopt=tsflags=nodocs \
        shim-x64 grub2-efi-x64 \
 && for d in /usr/lib/efi/shim/*/EFI/fedora /usr/lib/efi/grub2/*/EFI/fedora; do \
        [ -d "$d" ] || continue; \
        mv "$d" "$(dirname "$d")/cache22"; \
    done \
 && find /usr/lib/efi -mindepth 1 -maxdepth 5 -print

# ─── Stage 1: aur-builder ─────────────────────────────────────────
# Auto-detect packages cache22 lists that no configured repo provides,
# build them (plus transitive AUR deps) via paru into /aur-out. Stage
# is discarded after the main stage COPYs /aur-out, so base-devel /
# paru / cloned PKGBUILDs / etc. never reach the final image.
FROM ${BASE_IMAGE}:${BASE_TAG} AS aur-builder
ARG VARIANT_FAMILY
ARG VARIANT
ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} \
    KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH}" \
    KBUILD_BUILD_USER=cache22 \
    KBUILD_BUILD_HOST=cache22

COPY scripts/  /tmp/cache22-build/scripts/
COPY packages/ /tmp/cache22-build/packages/
RUN chmod +x /tmp/cache22-build/scripts/*.sh

RUN /tmp/cache22-build/scripts/inject-custom-repos-${VARIANT_FAMILY}.sh
RUN /tmp/cache22-build/scripts/build-aur-packages.sh \
        "/tmp/cache22-build/packages/${VARIANT_FAMILY}-common.txt" \
        "/tmp/cache22-build/packages/${VARIANT}.txt"

# ─── Stage 2: main image ──────────────────────────────────────────
FROM ${BASE_IMAGE}:${BASE_TAG}

ARG VARIANT_FAMILY=cachy
ARG VARIANT_TYPE=kde
ARG VARIANT=cachy-kde
ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} \
    KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH}" \
    KBUILD_BUILD_USER=cache22 \
    KBUILD_BUILD_HOST=cache22

LABEL containers.bootc=1
LABEL org.opencontainers.image.source=https://github.com/cmspam/cache22
LABEL org.opencontainers.image.description="cache22 — immutable bootc image (${VARIANT})"
LABEL org.opencontainers.image.licenses=Apache-2.0

COPY scripts/      /tmp/cache22-build/scripts/
COPY packages/     /tmp/cache22-build/packages/
COPY system_files/ /tmp/cache22-build/system_files/
RUN chmod +x /tmp/cache22-build/scripts/*.sh

# Move the pacman DB into /usr/lib/sysimage so the immutable image
# carries it. Must run before any pacman op.
RUN /tmp/cache22-build/scripts/rewrite-pacman-paths.sh

RUN /tmp/cache22-build/scripts/inject-custom-repos-${VARIANT_FAMILY}.sh

# Pull in AUR builds from stage 1; inject [cache22-aur] in pacman.conf
# (no-op if stage 1 had nothing to build).
COPY --from=aur-builder /aur-out /var/cache/pacman/cache22-aur
RUN if [ -f /var/cache/pacman/cache22-aur/.has-packages ]; then \
        /tmp/cache22-build/scripts/inject-cache22-aur-repo.sh; \
    else \
        echo "==> aur-builder produced no packages; skipping [cache22-aur] inject."; \
    fi \
 && mkdir -p /usr/share/cache22 \
 && if [ -f /var/cache/pacman/cache22-aur/cache22-aur-pkgs.txt ]; then \
        cp /var/cache/pacman/cache22-aur/cache22-aur-pkgs.txt /usr/share/cache22/aur-pkgs.txt; \
        echo "==> Persisted AUR sidecar: $(wc -l < /usr/share/cache22/aur-pkgs.txt) packages"; \
    fi

RUN cp -av --remove-destination /tmp/cache22-build/system_files/common/. / \
 && if [ -d "/tmp/cache22-build/system_files/${VARIANT}" ]; then \
        cp -av --remove-destination "/tmp/cache22-build/system_files/${VARIANT}/." /; \
    fi

RUN pacman -Syy --noconfirm \
 && pacman-key --populate

# sed strips inline comments + blank lines (so commented package lines
# don't pass through as bogus pkg names). Retry 5x: cachy/ALHP CDN
# sometimes serves a stale 404 while a new pkg propagates.
#
# --mount=type=secret,id=sbkey passes the cache22 SB private key into
# this RUN so DKMS hooks (fired by pacman for *-dkms packages) can sign
# the modules they build. /etc/dkms/framework.conf points them at this
# key path; modules get signed with the cache22 SB cert, MOK-trusted at
# boot, byte-stable across rebuilds.
RUN --mount=type=secret,id=sbkey,target=/run/secrets/sbkey,required=false \
    pkglist=$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' \
        "/tmp/cache22-build/packages/${VARIANT_FAMILY}-common.txt" \
        "/tmp/cache22-build/packages/${VARIANT}.txt") \
 && for attempt in 1 2 3 4 5; do \
        echo "==> pacman -S attempt $attempt"; \
        pacman -Syy --noconfirm; \
        if pacman -S --noconfirm --needed --disable-download-timeout $pkglist; then \
            echo "==> pacman -S succeeded on attempt $attempt"; \
            break; \
        fi; \
        if [ "$attempt" = "5" ]; then \
            echo "==> pacman -S failed after 5 attempts"; \
            exit 1; \
        fi; \
        echo "==> retrying in 60s"; \
        sleep 60; \
    done

# Re-apply overlay so post-install package files (e.g. ostree's
# prepare-root.conf) don't clobber our config.
RUN cp -av --remove-destination /tmp/cache22-build/system_files/common/. / \
 && if [ -d "/tmp/cache22-build/system_files/${VARIANT}" ]; then \
        cp -av --remove-destination "/tmp/cache22-build/system_files/${VARIANT}/." /; \
    fi

RUN /tmp/cache22-build/scripts/patch-ostree-dracut.sh
# faketime wrapper for dracut + sbsign — sbsign embeds wall-clock into
# the PE signature; without faketime the signed vmlinuz drifts every
# build. dracut goes under faketime too as defense in depth.
RUN pacman -S --noconfirm --needed libfaketime
RUN /tmp/cache22-build/scripts/generate-initramfs.sh

# Boot chain. See docs/SECUREBOOT.md.
# Pull Fedora's signed shim + grub2 from the fedora-bootloader stage.
# Vendor was renamed to "cache22" so bootupd's auto-detection picks
# our vendor name. Then have bootupd emit /usr/lib/bootupd/updates/
# EFI.json + payload tree so `bootupctl install/update/adopt` can
# operate on the deployed system.
COPY --from=fedora-bootloader /usr/lib/efi/  /usr/lib/efi/
# Build the bootupd payload tree + EFI.json manually. bootupd's own
# generate-update-metadata shells out to `rpm -q` for version info,
# which doesn't work on a pacman-based image. See script header.
RUN /tmp/cache22-build/scripts/generate-bootupd-metadata.sh
# Emit secureboot.cer (DER) for the installer to feed to mokutil --import.
RUN /tmp/cache22-build/scripts/build-sb-enrollment.sh
# sbsign each /usr/lib/modules/*/vmlinuz with the cache22 SB key so
# grub's shim_lock verifier accepts it once the user enrolls our cert
# in MOK on first boot.
RUN --mount=type=secret,id=sbkey,target=/run/secrets/sbkey,required=false \
    /tmp/cache22-build/scripts/sign-secureboot.sh

RUN VARIANT=${VARIANT} /tmp/cache22-build/scripts/finalize-image.sh

RUN bootc container lint

# Strip [cache22-aur] from pacman.conf since the file:// repo it
# points at is about to be removed. The block (header + 2 lines)
# ends at the next blank line. Sed is a no-op when absent (cachy
# variants and arch-server skip the inject entirely).
RUN sed -i '/^\[cache22-aur\]/,/^$/d' /etc/pacman.conf \
 && rm -rf /tmp/cache22-build /var/cache/pacman/cache22-aur
