# cache22 image build. See docs/IMAGE_BUILD.md.
#
# Build args: VARIANT_FAMILY (cachy|arch), VARIANT (e.g. arch-kde-gaming-nvidia).
# CI passes both. The manifest at packages/manifests/${VARIANT}.manifest names
# the layers to install, in order; package and system_files content for each
# layer live under packages/layers/${VARIANT_FAMILY}/<layer>.txt and
# system_files/layers/${VARIANT_FAMILY}/<layer>/.

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
    KBUILD_BUILD_HOST=cache22 \
    NV_BUILD_USER=cache22 \
    NV_BUILD_HOST=cache22-build

COPY scripts/  /tmp/cache22-build/scripts/
COPY packages/ /tmp/cache22-build/packages/
RUN chmod +x /tmp/cache22-build/scripts/*.sh

RUN /tmp/cache22-build/scripts/inject-custom-repos-${VARIANT_FAMILY}.sh
RUN /tmp/cache22-build/scripts/build-aur-packages.sh \
        --family "${VARIANT_FAMILY}" \
        --manifest "/tmp/cache22-build/packages/manifests/${VARIANT}.manifest" \
        --layers-dir "/tmp/cache22-build/packages/layers/${VARIANT_FAMILY}"

# ─── Stage 2: main image ──────────────────────────────────────────
FROM ${BASE_IMAGE}:${BASE_TAG}

ARG VARIANT_FAMILY=cachy
ARG VARIANT=cachy-kde-gaming-nvidia
ARG SOURCE_DATE_EPOCH=0
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} \
    KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH}" \
    KBUILD_BUILD_USER=cache22 \
    KBUILD_BUILD_HOST=cache22 \
    NV_BUILD_USER=cache22 \
    NV_BUILD_HOST=cache22-build

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

# Apply common system_files plus every layer overlay listed in the
# manifest, in manifest order (later layers override earlier ones).
RUN /tmp/cache22-build/scripts/apply-system-files.sh \
        --family "${VARIANT_FAMILY}" \
        --manifest "/tmp/cache22-build/packages/manifests/${VARIANT}.manifest" \
        --common-dir /tmp/cache22-build/system_files/common \
        --layers-dir "/tmp/cache22-build/system_files/layers/${VARIANT_FAMILY}" \
        --root /

RUN pacman -Syy --noconfirm \
 && pacman-key --populate

# Pin the hostname returned by `hostname` (the shell command) so build-
# time tools that shell out to it see a stable value. nvidia-open-dkms
# bakes "Release Build (root@<HOSTNAME>)" into nvidia.ko's .modinfo,
# which then drives a different .note.gnu.build-id and module signature
# every build. /usr/local/bin precedes /usr/bin in PATH so this shim
# overrides the real binary; finalize-image.sh removes it before
# bootc-lint runs.
RUN install -d /usr/local/bin \
 && printf '#!/bin/sh\nexec echo cache22-build\n' > /usr/local/bin/hostname \
 && chmod +x /usr/local/bin/hostname

# Expand the manifest into a deduplicated package list, then upgrade the
# base and install the list in one transaction. -u (full upgrade) is
# required: the base image ships packages (e.g. systemd-sysvcompat) with
# exact versioned deps, and installing the list pulls newer versions of
# their dependencies. A bare -S would leave the preinstalled packages
# behind and break on the version mismatch (partial-upgrade hazard).
# Retry up to 5x for transient mirror 404s or mid-sync DB inconsistency.
RUN pkglist=$(/tmp/cache22-build/scripts/expand-manifest.sh \
        --family "${VARIANT_FAMILY}" \
        --manifest "/tmp/cache22-build/packages/manifests/${VARIANT}.manifest" \
        --layers-dir "/tmp/cache22-build/packages/layers/${VARIANT_FAMILY}") \
 && for attempt in 1 2 3 4 5; do \
        echo "==> pacman -Syu attempt $attempt"; \
        pacman -Syy --noconfirm; \
        if pacman -Su --noconfirm --needed --disable-download-timeout $pkglist; then \
            echo "==> pacman -Syu succeeded on attempt $attempt"; \
            break; \
        fi; \
        if [ "$attempt" = "5" ]; then \
            echo "==> pacman -Syu failed after 5 attempts"; \
            exit 1; \
        fi; \
        echo "==> retrying in 60s"; \
        sleep 60; \
    done

# systemd-sysusers run inside a container stamps shadow sp_lstchg=0
# ("password must be changed now") on accounts it creates. For the Plasma
# login-manager session user that makes PAM reject user@<uid>.service, which
# blocks the logind seat and DRM handoff so the Wayland session never comes
# up on first boot. Lock the account and set a fixed non-zero last-changed
# date (kept constant for reproducible rebuilds) with age/inactivity expiry
# disabled. No-op on variants where the user does not exist.
RUN if id plasmalogin >/dev/null 2>&1; then \
        passwd -l plasmalogin || true; \
        chage -d 1 -M -1 -I -1 plasmalogin; \
    fi

# Re-apply layered overlay so post-install package files (e.g. ostree's
# prepare-root.conf) don't clobber our config.
RUN /tmp/cache22-build/scripts/apply-system-files.sh \
        --family "${VARIANT_FAMILY}" \
        --manifest "/tmp/cache22-build/packages/manifests/${VARIANT}.manifest" \
        --common-dir /tmp/cache22-build/system_files/common \
        --layers-dir "/tmp/cache22-build/system_files/layers/${VARIANT_FAMILY}" \
        --root /

RUN /tmp/cache22-build/scripts/patch-ostree-dracut.sh
RUN /tmp/cache22-build/scripts/generate-initramfs.sh

# No SB signing or bootloader binaries shipped — sd-boot + UKI are
# assembled and signed at install / bootc-upgrade time by
# /usr/libexec/cache22/resign-uki against the per-machine sbctl key.
# See docs/SECUREBOOT.md.

RUN VARIANT=${VARIANT} /tmp/cache22-build/scripts/finalize-image.sh

RUN bootc container lint

# Strip [cache22-aur] from pacman.conf since the file:// repo it
# points at is about to be removed. The block (header + 2 lines)
# ends at the next blank line. Sed is a no-op when absent.
RUN sed -i '/^\[cache22-aur\]/,/^$/d' /etc/pacman.conf \
 && rm -rf /tmp/cache22-build /var/cache/pacman/cache22-aur
