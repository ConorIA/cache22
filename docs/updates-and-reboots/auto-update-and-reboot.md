---
title: Auto-Update and Auto-Reboot
parent: Updates and Reboots
nav_order: 4
---

# Auto-Update and Auto-Reboot

cache22 ships two independent helpers for unattended updates:

- **`cache22-autoupdate`** schedules `cache22-update` on a systemd timer. It fetches and stages updates. It never reboots.
- **`cache22-autoreboot`** schedules a reboot window. At each firing it checks whether a staged update is ready and reboots if conditions are met.

Both are opt-in. Neither is enabled by default.

The split is intentional: staging is safe to do at any time. Rebooting is a stateful operation that should respect active sessions and time-of-day preferences.

## cache22-autoupdate

### Synopsis

```
sudo cache22-autoupdate enable [--profile PROFILE] [--schedule SPEC] [--no-app-updates]
sudo cache22-autoupdate disable
sudo cache22-autoupdate status
```

### Profiles

Two named profiles are picked automatically based on whether the system's default-target is graphical or multi-user:

| Profile | Trigger |
|---|---|
| `default-desktop` | 1 hour after boot, then daily after each firing. |
| `default-server` | `OnCalendar=daily` (00:00 UTC) + 2-hour random delay. |

Both profiles have `Persistent=true` (catches missed firings after sleep or shutdown) and `Restart=on-failure RestartSec=60s` with 3 retries (handles cases where the network is not yet up at wake).

### Examples

Enable with the auto-picked profile:

```
sudo cache22-autoupdate enable
```

Force a specific profile:

```
sudo cache22-autoupdate enable --profile default-server
```

Use a custom `OnCalendar` value:

```
sudo cache22-autoupdate enable --schedule '*-*-* 03:00'    # Every day at 03:00 local time.
sudo cache22-autoupdate enable --schedule weekly            # Weekly.
sudo cache22-autoupdate enable --schedule 'Mon *-*-* 04:00' # Mondays at 04:00.
```

Disable app updates (OS only):

```
sudo cache22-autoupdate enable --no-app-updates
```

Check current state:

```
sudo cache22-autoupdate status
```

Output shows the active profile or schedule, when the timer last fired, when it next fires, and the result of the last update.

Disable entirely:

```
sudo cache22-autoupdate disable
```

### Configuration files

`cache22-autoupdate enable` writes:

- `/etc/cache22/autoupdate.conf` containing `APP_UPDATES=yes|no`.
- `/etc/systemd/system/cache22-autoupdate.timer.d/cache22.conf` containing the `OnCalendar=` and `RandomizedDelaySec=` overrides.

To edit by hand, modify the files and run `sudo systemctl daemon-reload` followed by `sudo systemctl restart cache22-autoupdate.timer`.

## cache22-autoreboot

### Synopsis

```
sudo cache22-autoreboot enable --at SPEC [--window DURATION] [--allow-active-sessions]
sudo cache22-autoreboot disable
sudo cache22-autoreboot status
```

### Conditions for reboot

When the timer fires, the helper polls for these conditions:

1. A staged deploy exists (`bootc status .status.staged != null`).
2. The most recent `cache22-autoupdate.service` run did not fail.
3. No active sessions are blocking, unless `--allow-active-sessions` was set.

If all three are satisfied, the helper broadcasts a 5-minute warning to logged-in users (via `wall`) and then calls `cache22-reboot`. The strategy is selected by `cache22-reboot`'s auto-pick logic, which reads `/etc/cache22/reboot.conf`.

If a session blocks the reboot, the helper polls again at `POLL_INTERVAL` (default 60 sec) until the window expires. If the window expires with sessions still active, the helper exits and waits for the next OnCalendar firing.

### Examples

Reboot every day at 04:00 if a staged update is ready:

```
sudo cache22-autoreboot enable --at 'daily 04:00'
```

Note: systemd's calendar grammar does not accept `daily 04:00` as a single token in all versions. Equivalent forms that always work:

```
sudo cache22-autoreboot enable --at '04:00'
sudo cache22-autoreboot enable --at '*-*-* 04:00:00'
```

Sundays only at 03:00:

```
sudo cache22-autoreboot enable --at 'Sun *-*-* 03:00:00'
```

Tuesdays and Saturdays at 16:00 with a one-hour window for sessions to end:

```
sudo cache22-autoreboot enable --at 'Tue,Sat *-*-* 16:00:00' --window 1h
```

Always reboot, even with active sessions:

```
sudo cache22-autoreboot enable --at '04:00' --allow-active-sessions
```

Check the current state:

```
sudo cache22-autoreboot status
```

Disable entirely:

```
sudo cache22-autoreboot disable
```

### Configuration files

`cache22-autoreboot enable` writes:

- `/etc/cache22/autoreboot.conf` containing `WINDOW=` and `ALLOW_ACTIVE_SESSIONS=`.
- `/etc/systemd/system/cache22-autoreboot.timer.d/cache22.conf` containing the `OnCalendar=` override.

The reboot strategy itself (soft, kexec, hard) is read from `/etc/cache22/reboot.conf` at reboot time. cache22-autoreboot does not own that setting.

## Combined daily update + reboot

A common configuration: fetch updates at 05:00, reboot at 05:30 if anything is staged.

```
sudo cache22-autoupdate enable --schedule '05:00' --no-app-updates
sudo cache22-autoreboot enable --at '05:30' --window 30m
```

The 30-minute gap gives the autoupdate run time to complete (typical fetch + stage is 1-3 minutes; the gap is large because flaky networks can stretch it). The window lets autoreboot retry through the half-hour if a session is briefly active.

To use kexec for kernel-changing updates in this configuration:

```
echo 'KERNEL_CHANGE_STRATEGY=kexec' | sudo tee -a /etc/cache22/reboot.conf
```

If the system uses LUKS+TPM, also enroll a PCR 7 keyslot so kexec auto-unlocks. See [TPM and LUKS](../../boot-and-security/tpm-luks/).

## Alternative: bootc's own timer

The upstream bootc package ships its own fetch-apply timer:

```
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

Same fetch + stage behavior. It does not run flatpak or distrobox updates, does not refresh the cache22 pending-reboot banner, and does not compose with `cache22-autoreboot` for window-based reboots (it calls `bootc upgrade --apply` directly).

Use the bootc timer if cache22-autoupdate's profile or scheduling layer is not wanted.

## See also

- [`cache22-reboot`](../cache22-reboot/) for the reboot strategy selection used by autoreboot.
- [Three Reboot Paths](../three-reboot-paths/) for what each strategy does.
- [TPM and LUKS](../../boot-and-security/tpm-luks/) for unattended-reboot LUKS unlock configuration.
