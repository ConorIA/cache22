#!/usr/bin/env bash
# Run by cache22-autoupdate.service. Reads /etc/cache22/autoupdate.conf
# (sourced by the systemd unit's EnvironmentFile=) and invokes
# cache22-update with the right flags.

set -uo pipefail

ARGS=()
[[ "${APP_UPDATES:-yes}" == "yes" ]] && ARGS+=(--app-updates)

# --if-idle skips silently if a manual cache22-update already holds the
# /var/lock/cache22-update.lock flock. Manual run wins; we'll try again
# on the next timer firing.
exec /usr/bin/cache22-update --if-idle "${ARGS[@]}"
