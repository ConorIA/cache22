---
title: Health Checks
parent: System Ops
nav_order: 2
---

# Health Checks

`cache22-healthcheck` runs health-check scripts after every boot. After 3 consecutive failed boots it triggers `bootc rollback` to revert to the previous deployment.

The default check verifies that the services you declare as critical are active. If you declare none, the health check does nothing and never rolls back. Connectivity is not checked, because an upstream outage is not a reason to roll back the operating system, and a reboot would not fix it.

## How it works

A timer (`cache22-healthcheck.timer`) fires the service (`cache22-healthcheck.service`) 2 minutes after every boot. The delay lets services reach a steady state before the check runs.

The service runs every executable in `/etc/cache22/healthcheck.d/required.d/`. If any check exits non-zero, the boot is recorded as failed.

A counter at `/var/lib/cache22/healthcheck/fail-counter` tracks consecutive failures. It increments on each failed boot and resets to zero on each successful boot.

When the counter reaches 3, the service:

1. Calls `bootc rollback` to flip the booted and rollback deployments.
2. Resets the counter to zero.
3. Calls `systemctl reboot` to apply the rollback.

The next boot lands on the previous deployment, which was the booted deployment before the failing upgrade.

## Declaring critical services

The shipped check `10-critical-services` reads `/etc/cache22/healthcheck.services`. List one systemd unit per line; blank lines and text after `#` are ignored. The boot passes only when every listed unit is active.

```
sudo nano /etc/cache22/healthcheck.services
```

```
sshd.service
podman.service
nginx.service
```

An empty or absent list passes, so out of the box the health check is a no-op. Declare the services that define a healthy system for this host to opt in to auto-rollback.

## Adding custom checks

For checks beyond service state, drop an executable script into `/etc/cache22/healthcheck.d/required.d/`:

```
sudo nano /etc/cache22/healthcheck.d/required.d/20-mychecks
sudo chmod +x /etc/cache22/healthcheck.d/required.d/20-mychecks
```

The script receives no arguments. Exit 0 to pass, non-zero to fail. Output goes to the service journal.

Ready-to-copy examples live in `/usr/share/cache22/healthcheck-examples/`. Copy one into `required.d/` to enable it:

```
sudo cp /usr/share/cache22/healthcheck-examples/01-system-running \
        /etc/cache22/healthcheck.d/required.d/
```

Useful patterns:

### Specific port is listening

```bash
#!/usr/bin/env bash
ss -tln | grep -q ':22 '
```

### Application-level check

```bash
#!/usr/bin/env bash
curl -fsS http://localhost:8080/health | grep -q '"status":"ok"'
```

### Filesystem space

```bash
#!/usr/bin/env bash
# Fail if root is more than 95% full.
[ "$(df --output=pcent / | tail -1 | tr -d '% ')" -lt 95 ]
```

A connectivity check (for example `ping -c1 1.1.1.1`) is possible but discouraged: an upstream outage that persists across 3 boots would roll the system back without fixing anything.

## Examples

### Check the current consecutive-failure count

```
cat /var/lib/cache22/healthcheck/fail-counter
```

Zero means the last boot passed. A non-zero value means the last boot failed; the system rolls back when the count reaches 3.

### Force a rollback now

```
sudo bootc rollback
sudo cache22-reboot
```

### Run the health check immediately, without waiting for the timer

```
sudo systemctl start cache22-healthcheck.service
sudo journalctl -u cache22-healthcheck.service -b
```

### Disable auto-rollback entirely

Leave `/etc/cache22/healthcheck.services` empty and add no custom checks, or mask the timer:

```
sudo systemctl mask --now cache22-healthcheck.timer
```

## Layout details

| Path | Purpose |
|---|---|
| `/etc/cache22/healthcheck.services` | Critical-services list read by the default check. |
| `/etc/cache22/healthcheck.d/required.d/*` | Per-check scripts. All must pass. |
| `/usr/share/cache22/healthcheck-examples/*` | Opt-in example checks to copy into `required.d/`. |
| `/var/lib/cache22/healthcheck/fail-counter` | Consecutive-failure counter. |
| `/usr/lib/systemd/system/cache22-healthcheck.timer` | Timer (2 min after boot). |
| `/usr/lib/systemd/system/cache22-healthcheck.service` | Service that runs the checks. |
| `/usr/bin/cache22-healthcheck` | The script invoked by the service. |

To see the timer's status:

```
systemctl list-timers cache22-healthcheck.timer
```

## Notes

- After a successful boot the counter resets before the next boot's check runs, so a single bad boot followed by a good boot clears the count.
- Rollback is one-way: after auto-rollback the deployment that failed becomes the rollback target. Run `bootc rollback` again to flip back.

## See also

- [Pinning and Rollback](../../updates-and-reboots/pinning-and-rollback/) for the full rollback mechanics.
- [`cache22-update`](../../updates-and-reboots/cache22-update/) for the upgrade flow that introduces deployments which may fail health checks.
- [Repair](../repair/) for recovery when even the rollback deployment will not boot.
