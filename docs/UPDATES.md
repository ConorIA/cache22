# cache22 — how updates work

## Where updates come from

The installed system records its source image in `/sysroot/.bootc-aleph.json` (`target-image` field) and the stateroot origin file. Both point to whatever variant was installed (e.g. `ghcr.io/cmspam/cache22-cachy-kde:rolling`).

CI rebuilds and re-pushes the `rolling` tag for all four variants on every push to `main` that touches `Containerfile`, `packages/**`, `system_files/**`, `scripts/**`, or the workflow itself, plus a daily cron at 18:00 UTC.

## Recommended: `cache22-update`

```
sudo cache22-update              # pull + stage; finalize + UKI build at next shutdown
sudo cache22-update --reboot     # ... then reboot via cache22-reboot (auto-soft when same-kernel)
sudo cache22-update --check      # read-only status check
sudo cache22-update --app-updates  # also flatpak update + distrobox upgrade --all
```

Runs `bootc upgrade --check` first (skips work when the registry has nothing new), then `bootc upgrade` to fetch + stage. Returns immediately — finalize and UKI build are deferred to shutdown via the standard `ostree-finalize-staged.service` path, with our `50-cache22-uki.conf` drop-in appending a second `ExecStop=` for the UKI build right after ostree writes the BLS entry. Same job, same timeout semantics, same shutdown-blocking guarantees as ostree's own finalize.

## Switching variants: `cache22-rebase`

```
sudo cache22-rebase                          # interactive picker
sudo cache22-rebase --variant cachy-server   # by id
sudo cache22-rebase --image ghcr.io/foo:bar  # arbitrary OCI ref
sudo cache22-rebase --reboot                 # reboot when done
```

Same shape as `cache22-update`: `bootc switch` stages the new image; finalize + UKI build happen at next shutdown. Flips between cachy/arch families and kde/server types without reinstalling.

The picker pulls `variants.json` live from `raw.githubusercontent.com/cmspam/cache22/main/variants.json` so new variants show up without a system update; falls back to `/etc/cache22/variants.json` (baked into the image) when offline.

Rebasing to a non-cache22 bootc image (e.g. `ghcr.io/ublue-os/bazzite:latest`) is **not supported** — the new image won't have `cache22-resign-uki` and won't be expecting sd-boot + per-machine UKI on the ESP. For cross-bootc moves use `cache22-repair` from the cache22 live ISO.

## Manual / advanced

```
sudo bootc upgrade        # fetch + stage; finalize + UKI build at next shutdown
sudo cache22-reboot       # auto-soft when same-kernel, hard otherwise
sudo bootc rollback       # swap staged + booted; UKI ordering updates at next shutdown
```

`cache22-reboot` reads `bootc status .status.staged.softRebootCapable` to decide between soft-reboot, kexec, and hard reboot. Soft-reboot uses our own `/usr/libexec/cache22/prepare-soft-reboot` to populate `/run/nextroot` (since ostree's own `prepare-soft-reboot` only supports the composefs backend, which cache22 doesn't use yet).

## Bootloader updates

The runtime hook (`/usr/libexec/cache22/resign-uki`) re-signs and re-installs sd-boot whenever the in-image binary at `/usr/lib/systemd/boot/efi/systemd-bootx64.efi` is newer than the on-ESP copy. systemd's stock `systemd-boot-update.service` is masked because it would copy the unsigned upstream binary over our locally-signed one.

## Hands-off updates

**`cache22-autoupdate`** schedules `cache22-update` on a timer. Two built-in profiles, picked automatically based on whether the default target is graphical or multi-user:

| Profile | Trigger |
|---|---|
| `default-desktop` | 1h after boot, then 1d after each firing |
| `default-server` | `OnCalendar=daily` (00:00 UTC) + 2h random delay |

```bash
sudo cache22-autoupdate enable                          # auto-pick profile
sudo cache22-autoupdate enable --profile default-server
sudo cache22-autoupdate enable --schedule '*-*-* 03:00' # custom OnCalendar
sudo cache22-autoupdate disable
sudo cache22-autoupdate status
```

**`cache22-autoreboot`** schedules a reboot window. At each firing it waits until a deployment is staged, the last autoupdate run didn't fail, and no active sessions are blocking — then broadcasts a 5-minute warning and reboots.

```bash
sudo cache22-autoreboot enable --at 'daily 04:00'
sudo cache22-autoreboot enable --at 'Sun 03:00' --window 1h
sudo cache22-autoreboot disable
sudo cache22-autoreboot status
```

## How rollback works

`bootc rollback` flips the staged/booted/rollback ordering inside bootc's state. UKIs aren't immediately regenerated — instead, on next shutdown the `ostree-finalize-staged.service` drop-in re-runs `resign-uki`, which reads the now-flipped BLS entries and rewrites UKIs with updated `.osrel VERSION_ID` priorities so sd-boot's auto-default picks the rolled-back deploy. UKIs for live deploys are kept; UKIs for pruned deploys are GC'd only after every desired UKI is confirmed present. (To force an immediate rebuild without rebooting, run `sudo systemctl start cache22-resign-uki.service`.)
