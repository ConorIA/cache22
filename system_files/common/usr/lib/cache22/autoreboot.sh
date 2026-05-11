#!/usr/bin/env bash
# Run by cache22-autoreboot.service. Polls within the configured window
# until reboot conditions are met or the window expires.
#
# Conditions for reboot (all must hold):
#   1. A deployment is staged (bootc status shows staged != null)
#   2. The most recent cache22-autoupdate.service run did NOT fail
#   3. No active sessions block (unless ALLOW_ACTIVE_SESSIONS=yes)
#
# Reboot is delegated to cache22-reboot, which auto-picks soft-reboot
# (kernel unchanged) or honors KERNEL_CHANGE_STRATEGY in
# /etc/cache22/reboot.conf when the kernel changed. A 5-minute wall
# warning is broadcast first so logged-in users can save work.

set -uo pipefail

WINDOW="${WINDOW:-30m}"
ALLOW_ACTIVE_SESSIONS="${ALLOW_ACTIVE_SESSIONS:-no}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"

parse_duration() {
    # Returns seconds. Accepts 30s, 30m, 2h, or a bare integer (seconds).
    local s="$1"
    case "$s" in
        *h)  echo $(( ${s%h} * 3600 )) ;;
        *m)  echo $(( ${s%m} * 60 )) ;;
        *s)  echo "${s%s}" ;;
        *)   echo "$s" ;;
    esac
}

is_staged() {
    # Standard bootc/ostree model: a staged deploy lives in bootc's
    # `staged` slot until shutdown, when ostree-finalize-staged.service
    # writes the BLS entry. Either side counts as "an update is waiting".
    local staged
    staged=$(bootc status --json 2>/dev/null | jq -r '.status.staged // "null"' 2>/dev/null)
    [[ -n "$staged" && "$staged" != "null" ]]
}

last_update_failed() {
    systemctl is-failed --quiet cache22-autoupdate.service
}

active_sessions_present() {
    # Block on any logged-in user with an active session. Excludes
    # `lightdm`/`gdm`/`sddm`/`plasmalogin` greeter user sessions.
    local count
    count=$(loginctl list-sessions --no-legend 2>/dev/null \
        | awk '$3 != "" && $3 !~ /^(lightdm|gdm|sddm|plasmalogin|_systemd-timesync)$/ {print}' \
        | wc -l)
    (( count > 0 ))
}

window_seconds=$(parse_duration "$WINDOW")
end_time=$(( $(date +%s) + window_seconds ))

echo "cache22-autoreboot: window=${WINDOW} (${window_seconds}s), allow-active=${ALLOW_ACTIVE_SESSIONS}"

while (( $(date +%s) < end_time )); do
    if ! is_staged; then
        echo "no staged deployment, exiting (nothing to reboot for)"
        exit 0
    fi
    if last_update_failed; then
        echo "last cache22-autoupdate.service failed, skipping reboot"
        exit 0
    fi
    if [[ "$ALLOW_ACTIVE_SESSIONS" != "yes" ]] && active_sessions_present; then
        echo "active sessions present, polling again in ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
        continue
    fi
    echo "all clear; broadcasting 5-min reboot warning"
    wall "cache22 unattended reboot in 5 minutes for staged update"
    sleep 300
    # cache22-reboot auto-picks soft when capable, otherwise hard
    # (or kexec if KERNEL_CHANGE_STRATEGY=kexec). Fallback to
    # systemctl reboot covers the unlikely case of cache22-reboot
    # exiting nonzero before exec'ing into a real reboot.
    cache22-reboot || \
        { echo "cache22-reboot failed; falling back to systemctl reboot in 5s"; sleep 5; systemctl reboot; }
    exit 0
done

echo "window expired without reboot opportunity; will retry at next OnCalendar firing"
