#!/usr/bin/env bash
# Shared: drive ostree-finalize-staged synchronously so the new BLS
# entry lands on /boot before the wrapper returns. Used by cache22-update
# and cache22-rebase.
set -euo pipefail

echo "==> Finalizing staged deployment"
systemctl start ostree-finalize-staged.service

echo "[OK] Deployment ready. Reboot to apply."
