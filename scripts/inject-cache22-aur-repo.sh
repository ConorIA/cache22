#!/usr/bin/env bash
# Inject [cache22-aur] into pacman.conf as the lowest-priority repo so
# AUR-built fallbacks resolve only when no other configured repo provides
# the package. Called by the main Containerfile stage AFTER the aur-builder
# stage's /aur-out has been COPY'd into /var/cache/pacman/cache22-aur, and
# ONLY when that directory contains a .has-packages marker.
set -euo pipefail

PACMAN_CONF=/etc/pacman.conf

cat >> "$PACMAN_CONF" <<'EOF'

[cache22-aur]
SigLevel = Optional TrustAll
Server = file:///var/cache/pacman/cache22-aur
EOF

echo "==> [cache22-aur] injected; final repo order:"
grep -E '^\[' "$PACMAN_CONF"
