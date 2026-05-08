# cache22 pending-reboot banner for interactive shells.
# Sourced by /etc/profile on bash login (and equivalent for other shells).

# Fast read-only check; exits non-zero when nothing is staged so we
# stay silent on the common case.
if command -v cache22-changelog >/dev/null 2>&1 && cache22-changelog --check 2>/dev/null; then
    cat <<'EOF'

──────────────────────────────────────────────────────────
  cache22 update is staged — reboot to apply.
  Run `cache22-changelog` to see what changed.
──────────────────────────────────────────────────────────
EOF
fi
