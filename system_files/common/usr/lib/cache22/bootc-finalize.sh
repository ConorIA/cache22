#!/usr/bin/env bash
# Shared: drive ostree-finalize-staged synchronously so the new BLS
# entry lands on /boot before the wrapper returns. Used by cache22-update
# and cache22-rebase.
#
# ostree-finalize-staged.service does its work in ExecStop (it's a
# shutdown-time service), so `systemctl start` is a no-op. Call the
# ostree binary directly. It's a no-op + exit 0 when nothing is staged.
set -euo pipefail

echo "==> Finalizing staged deployment"
ostree admin finalize-staged

echo "[OK] Deployment ready. Reboot to apply."
