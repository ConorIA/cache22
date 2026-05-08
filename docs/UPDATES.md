# cache22 — how updates work

## Where updates come from

The installed system records its source image in `/sysroot/.bootc-aleph.json` (`target-image` field) and the stateroot origin file. Both point to whatever variant was installed (e.g. `ghcr.io/cmspam/cache22-cachy-kde:rolling`).

CI rebuilds and re-pushes the `rolling` tag for all four variants on every push to `main` that touches `Containerfile`, `packages/**`, `system_files/**`, `scripts/**`, or the workflow itself, plus a daily cron at 18:00 UTC.

## Recommended: `cache22-update`

```
sudo cache22-update              # pull + stage + finalize, no reboot
sudo cache22-update --reboot     # ... then reboot
sudo cache22-update --check      # read-only status check
sudo cache22-update --app-updates  # also flatpak update + distrobox upgrade --all
```

Runs `bootc upgrade` then immediately calls `ostree-finalize-staged` so the new BLS entry lands on `/boot` before the script returns. Power loss after the wrapper finishes but before reboot is benign — grub reads whichever entry is current on `/boot/loader.X/entries/`, and ostree's atomic loader-symlink swap guarantees consistency.

## Switching variants: `cache22-rebase`

```
sudo cache22-rebase                          # interactive picker
sudo cache22-rebase --variant cachy-server   # by id
sudo cache22-rebase --image ghcr.io/foo:bar  # arbitrary OCI ref
sudo cache22-rebase --reboot                 # reboot when done
```

Same finalize chain as `cache22-update`. Lets you flip between cachy/arch families and kde/server types without reinstalling.

The picker pulls `variants.json` live from `raw.githubusercontent.com/cmspam/cache22/main/variants.json` so new variants show up without a system update; falls back to `/etc/cache22/variants.json` (baked into the image) when offline.

Rebasing to a non-cache22 bootc image (e.g. `ghcr.io/ublue-os/bazzite:latest`) works — grub on the ESP reads whatever BLS entries the new image writes.

## Manual / advanced

```
sudo bootc upgrade        # fetch + stage; finalize happens at shutdown
sudo systemctl reboot     # apply
sudo bootc rollback       # swap staged + booted; reboot to confirm
```

The wrappers above move the finalize step earlier (while the system is up), which is safer than relying on shutdown timing.

## Bootloader updates

`bootloader-update.service` (from the `bootupd` package, enabled via `system_files/.../50-cache22.preset`) runs `bootupctl update` on every boot. It's idempotent — a no-op when the ESP already matches `/usr/lib/efi/` in the running image. When a `bootc upgrade` delivers newer Fedora shim/grub binaries, the next reboot refreshes the ESP automatically. No separate command needed.

## Hands-off updates

**`cache22-autoupdate`** (recommended) schedules `cache22-update` on a timer. Two built-in profiles, picked automatically based on whether the default target is graphical or multi-user:

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
sudo cache22-autoreboot enable --at 'daily 04:00'       # daily 4am
sudo cache22-autoreboot enable --at 'Sun 03:00' --window 1h
sudo cache22-autoreboot disable
sudo cache22-autoreboot status
```

**Bare bootc timer** (minimal alternative — no flatpak/distrobox, no autoreboot integration, no staging banners):

```bash
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

## How the boot chain stays consistent

Kernels + initramfs + BLS entries live in exactly one place (`/boot/ostree/<deploy>/` + `/boot/loader.X/entries/`). ostree/bootc handles all of that; cache22 adds no bootloader glue of its own. The ESP is managed by bootupd. `bootc upgrade` writes new BLS entries; grub reads them on next boot.

The rechunker means each upgrade downloads only the layers whose digest changed since the previous rolling tag — typical daily delta is ~100–300 MB.
