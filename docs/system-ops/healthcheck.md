---
title: Health Checks
parent: System Ops
nav_order: 2
---

# Health Checks

`cache22-healthcheck` runs user-defined health-check scripts after every boot. After 3 consecutive failed boots, it triggers `bootc rollback` to revert to the previous deploy.

## How it works

A timer (`cache22-healthcheck.timer`) fires the service (`cache22-healthcheck.service`) 2 minutes after every boot. The 2-minute delay lets the system reach a steady state before checking.

The service runs every executable in `/etc/cache22/healthcheck.d/required.d/`. If any check exits non-zero, the boot is recorded as failed.

A counter at `/var/lib/cache22/healthcheck-bad-boots` tracks consecutive failures. The counter increments on each failed boot and resets to zero on each successful boot.

When the counter reaches 3, the service:

1. Calls `bootc rollback` to flip the booted and rollback deploys.
2. Resets the counter to zero.
3. Calls `systemctl reboot` to apply the rollback.

The next boot will land on the previous deploy, which presumably is known-good (it was the booted deploy before the failing upgrade).

## Default checks

cache22 ships these default checks in `/etc/cache22/healthcheck.d/required.d/`:

| Check | What it tests |
|---|---|
| `01-system-running` | `systemctl is-system-running` returns `running` or `degraded`. |
| `02-network` | `NetworkManager.service` is active. |

`degraded` is treated as a pass because some non-critical service failures should not trigger rollback. To be stricter, edit `01-system-running` to fail on `degraded` too.

## Adding custom checks

Drop an executable script into `/etc/cache22/healthcheck.d/required.d/`:

```
sudo nano /etc/cache22/healthcheck.d/required.d/03-mychecks
sudo chmod +x /etc/cache22/healthcheck.d/required.d/03-mychecks
```

The script receives no arguments. It must exit 0 for pass, non-zero for fail. Output to stdout/stderr is captured by the service journal.

Example checks:

### Network connectivity

```bash
#!/usr/bin/env bash
# Verify outbound network reachability.
ping -c 1 -W 5 1.1.1.1 >/dev/null
```

### Specific service is active

```bash
#!/usr/bin/env bash
# Verify caddy is running.
systemctl is-active caddy.service
```

### Specific port is listening

```bash
#!/usr/bin/env bash
# Verify SSH is listening.
ss -tln | grep -q ':22 '
```

### Application-level check

```bash
#!/usr/bin/env bash
# Verify the API responds.
curl -fsS http://localhost:8080/health | grep -q '"status":"ok"'
```

### Filesystem space

```bash
#!/usr/bin/env bash
# Fail if root is more than 95% full.
[ "$(df --output=pcent / | tail -1 | tr -d '% ')" -lt 95 ]
```

## Examples

### Check current consecutive-failure count

```
cat /var/lib/cache22/healthcheck-bad-boots
```

Zero means the last boot passed. A non-zero value means the last boot failed; the system will roll back when the count hits 3.

### Force a rollback now (without waiting for 3 failures)

```
sudo bootc rollback
sudo cache22-reboot
```

### Manually trigger a health check (bypassing the 2-minute timer)

```
sudo systemctl start cache22-healthcheck.service
```

The service runs immediately. Output appears in the journal:

```
sudo journalctl -u cache22-healthcheck.service -b
```

### Disable the auto-rollback (keep the checks running but do not act on failures)

Edit `/etc/cache22/healthcheck.d/required.d/01-system-running` (or any check) to print but always pass. Or disable the timer:

```
sudo systemctl disable cache22-healthcheck.timer
```

Disabling is not recommended; rollback after 3 bad boots is a meaningful safety net.

## Layout details

| Path | Purpose |
|---|---|
| `/etc/cache22/healthcheck.d/required.d/*` | Per-check scripts. All must pass. |
| `/var/lib/cache22/healthcheck-bad-boots` | Consecutive failure counter. |
| `/usr/lib/systemd/system/cache22-healthcheck.timer` | Timer (2 min after boot). |
| `/usr/lib/systemd/system/cache22-healthcheck.service` | Service that runs the checks. |
| `/usr/bin/cache22-healthcheck` | The script invoked by the service. |

To see the timer's status:

```
systemctl list-timers cache22-healthcheck.timer
```

## Notes

- The service is `WantedBy=cache22-healthcheck.timer` rather than `WantedBy=multi-user.target` to avoid a deadlock where the check waits on its own startup.
- After a successful boot, the counter resets BEFORE the next boot's check runs. This means a single bad boot followed by 2 good boots resets the count.
- Rollback is one-way: after auto-rollback, the deploy that failed is now the rollback target. To re-attempt the failed deploy, use `bootc rollback` again to flip back.

## See also

- [Pinning and Rollback](../../updates-and-reboots/pinning-and-rollback/) for the full rollback mechanics.
- [`cache22-update`](../../updates-and-reboots/cache22-update/) for the upgrade flow that introduces deploys that may fail health checks.
- [Repair](../repair/) for recovery when even the rollback deploy will not boot.
