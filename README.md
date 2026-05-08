# cache22

Immutable, atomic Linux desktop and server images built from Arch and CachyOS, delivered as OCI container images via [bootc](https://bootc-dev.github.io/bootc/). Your `/usr` is read-only and signed; updates are atomic with one-command rollback; the OS itself is just a container image you can swap in or out at boot.

> This is not an official or supported version of Arch or CachyOS, and, in fact, is fitting a square peg in a round hole, so please only use it if you know what you're doing.

## Variants

| Variant | Image | Base / kernel | Desktop |
| --- | --- | --- | --- |
| `cachy-kde` | `ghcr.io/cmspam/cache22-cachy-kde:rolling` | CachyOS, `linux-cachyos-bore-lto` | KDE Plasma 6 |
| `cachy-server` | `ghcr.io/cmspam/cache22-cachy-server:rolling` | CachyOS, `linux-cachyos-bore-lto` | (headless) |
| `arch-kde` | `ghcr.io/cmspam/cache22-arch-kde:rolling` | Vanilla Arch + ALHP-rebuilt `linux` | KDE Plasma 6 |
| `arch-server` | `ghcr.io/cmspam/cache22-arch-server:rolling` | Vanilla Arch + ALHP-rebuilt `linux` | (headless) |

All variants ship with NVIDIA (open driver), AMD, and Intel GPU support; ZFS (cachy only); Realtek 2.5G (`r8125`); Bluetooth; printing (CUPS); SANE; fingerprint readers; CJK input via fcitx5; QEMU + libvirt + virt-manager; podman + docker + distrobox + incus.

KDE variants additionally include Steam, Lutris, gamemode, MangoHud, gamescope, and a SteamOS-style "gamescope mode" toggle.

## What's special

cache22 is intended as an Arch-based equivalent to [Bazzite](https://bazzite.gg/) — same atomic-image philosophy, same gaming/desktop focus, but built on the Arch/CachyOS userland instead of Fedora. Aimed at desktop and laptop use; **no Steam Deck or handheld-specific patches**.

A handful of upstream packages are rebuilt with patches that aren't in stock Arch or CachyOS:

- **[`gamescope-patched`](https://github.com/cmspam/gamescope-patched)** — fixes Steam remote-play under NVIDIA (the stock build produces a black screen with inverted colors). Pulled in automatically by `pacman -S gamescope`.
- **[`qemu-patched`](https://github.com/cmspam/qemu-patched)** — enables VA-API in the QEMU build so guest hardware video acceleration works. Pulled in automatically by `pacman -S qemu-desktop`.
- **[`xe-virt-repo`](https://github.com/cmspam/xe-virt-repo)** — patches `virglrenderer` to enable `drm_context_native` on Intel Xe so virtio-gpu native context works in guests. Repo ships both host (`xe-virt-host-v3`) and guest (`xe-virt-guest-v3`) packages — cache22 includes the host side; install the matching guest package inside Linux VMs you spin up.

Also pre-included on the desktop variants but worth calling out:

- **xone** kernel module + userland for Xbox One / Series controller support over USB and the wireless dongle (no proprietary firmware needed).
- **r8125** Realtek 2.5G ethernet driver, pre-built per-kernel — works out of the box on common motherboards where the in-tree `r8169` is flaky.
- **NVIDIA open driver** (`nvidia-open`), pre-built per-kernel on cachy variants and DKMS-built on arch variants — no manual driver dance after install.

## Installing

Two paths:

### 1. Live ISO installer (recommended for new installs)

Download the ISO from the [latest release](https://github.com/cmspam/cache22/releases/latest) and boot it. tty1 auto-logins root and shows a motd; run `cache22-install` to start. It walks you through:

- Variant pick (defaults to `cachy-kde`; the picker fetches the live variant catalog from this repo so the choices stay current without re-downloading the ISO)
- Disk pick + optional LUKS encryption
- User account, hostname, locale, timezone

Then it pulls the image (~8 GB), partitions, installs, and reboots into your new system.

### 2. `bootc switch` from another bootc system

If you're already on Fedora Silverblue / Kinoite / Bazzite / Bluefin / etc.:

```bash
sudo bootc switch ghcr.io/cmspam/cache22-cachy-kde:rolling
sudo systemctl reboot
```

This works, but the live ISO is the recommended path for one big reason: **Secure Boot.** The installer sets up Fedora's MS-signed shim + grub2 on your ESP via bootupd and queues the cache22 SB cert for MOK enrollment, so SB works with one password prompt at first boot — no firmware Setup Mode dance, no certificate juggling. Going via `bootc switch` from another distro keeps that distro's bootloader, so you'd have to wire up MOK enrollment yourself.

**We strongly recommend leaving Secure Boot ENABLED throughout the install.** The installer ISO itself is SB-bootable (it uses Fedora's MS-signed shim + Fedora-signed kernel), so you don't need to disable SB to run it, and keeping SB on the whole way makes the first-boot MokManager prompt fire automatically.

### Auto vs tmpfs scratch during install

The installer pulls the OCI image into a scratch area (~6 GB for server variants, ~12 GB for KDE) before laying it down on the target disk. By default in whole-disk mode it picks one of two strategies based on how much RAM your machine has:

- **tmpfs scratch** — RAM-backed. Faster install (no SSD writes for the scratch), zero wear on the target disk for the install itself, and the target's root partition is created at full size right away (no reclaim step). Picked automatically when MemAvailable is at least 14 GB for server variants or 20 GB for KDE variants.
- **Disk partition scratch** — a temporary 30 GB partition on the target disk that gets formatted, used, and then merged back into root at the end. Picked when there isn't enough RAM for tmpfs. Adds a few minutes of install time and ~10 GB of write traffic to the target.

Override the auto-detection with `--scratch tmpfs` (force RAM scratch even on lower-RAM systems — at your own risk of OOM) or `--scratch /dev/X` (use a specific partition; flips the installer into custom-partition mode).

## Secure Boot

cache22 uses the standard **shim + MOK** chain — same pattern Bazzite, Fedora, Ubuntu, and SUSE ship — so it works on stock OEM hardware without any firmware-Setup-Mode dance.

```
firmware (Microsoft keys, factory-shipped)
  → shim                (Microsoft-signed Fedora shim, in EFI db)
    → grub2             (Fedora-signed, trusted via shim's vendor_cert)
      → kernel          (cache22-signed, trusted via MOK enrollment)
```

Every kernel is signed at image build time with the cache22 SB key. You enroll the matching cert into MOK once, at first boot.

### What you do

1. **Leave Secure Boot ON when you install.** The installer ISO is SB-bootable (Fedora kernel + Fedora-signed bootloader); you don't have to disable SB to run it.
2. **Run `cache22-install`.** It handles everything: bootupd installs Fedora's signed shim + grub2 on your ESP, the cache22 cert lands at `/EFI/BOOT/sbcert.der`, and `mokutil --import` queues MOK enrollment.
3. **First reboot: MokManager appears (blue screen).** Type:
   ```
   Enroll MOK → Continue → Yes → password: cache22sb → Reboot
   ```
4. Done. Every boot verifies the cache22-signed kernel against the MOK-enrolled cert. Subsequent kernel updates come pre-signed in the image — no further enrollment needed.

If MokManager doesn't auto-launch or the password prompt fails, choose **"Enroll key from disk"** and pick `/EFI/BOOT/sbcert.der`.

### Post-install management

```bash
sudo cache22-secureboot status     # show SB state, MOK enrollment, kernel sig
sudo cache22-secureboot enroll     # (re-)queue MOK enrollment + force boot to MokManager
sudo cache22-secureboot unenroll   # queue MOK removal
```

Most users never need this — the installer handles enrollment. It's there for users who skipped enrollment, want to re-enroll after a key rotation, or want to remove the cert.

See [`docs/SECUREBOOT.md`](docs/SECUREBOOT.md) for the full chain details and threat model.

## Upgrading

```bash
sudo cache22-update              # pull, stage, finalize — no reboot
sudo cache22-update --reboot     # ... then reboot when done
sudo cache22-update --check      # is there an upgrade available?
sudo cache22-update --app-updates  # also: flatpak update + distrobox upgrade --all
```

Per-package layer rechunking means typical daily upgrades download only the layers whose contents actually changed (~100–300 MB), not the full multi-GB image.

Bootloader binaries (shim, grub2) on the ESP update automatically — `bootloader-update.service` runs `bootupctl update` on every boot, picking up any newer Fedora binaries that arrived in the new image. No separate command needed.

If something boots wrong, `sudo bootc rollback && sudo systemctl reboot` puts you back on the previous deployment. cache22 also runs healthchecks 2 minutes after every boot and auto-rolls-back after 3 consecutive failures (drop your own checks into `/etc/cache22/healthcheck.d/required.d/` to extend).

### Hands-off updates with optional auto-reboot

Two independent layers, both opt-in:

**Layer 1 — `cache22-autoupdate`** schedules `cache22-update` on a timer (fetch + stage, never reboots). Staged updates pile up across runs — re-running the timer just replaces the staged slot with the freshest image. When you eventually reboot (manually or via Layer 2), you boot directly into the latest staged image.

```bash
sudo cache22-autoupdate enable                                   # auto-pick profile
sudo cache22-autoupdate enable --profile default-desktop         # explicit
sudo cache22-autoupdate enable --profile default-server          # explicit
sudo cache22-autoupdate enable --schedule weekly                 # custom OnCalendar
sudo cache22-autoupdate enable --schedule '*-*-* 03:00'          # 3am every day
sudo cache22-autoupdate enable --no-app-updates                  # OS only, skip flatpak/distrobox
sudo cache22-autoupdate disable
sudo cache22-autoupdate status
```

Two named profiles, picked automatically based on whether the system default-target is graphical or multi-user:

| Profile | Trigger |
|---|---|
| `default-desktop` | 1h after boot, then 1d after each firing |
| `default-server` | `OnCalendar=daily` (00:00 UTC) + 2h random delay |

Both profiles have `Persistent=true` (catches missed firings after sleep/shutdown) and `Restart=on-failure RestartSec=60s × 3` (retries if network isn't up yet at wake).

`--schedule SPEC` (any systemd OnCalendar value) overrides the profile entirely.

**Layer 2 — `cache22-autoreboot`** schedules a reboot timer that fires within a configurable window. At each firing it polls until reboot conditions are met OR the window expires:

- A deployment is staged
- The most recent `cache22-autoupdate` run did NOT fail
- No active sessions are blocking (default — overridable)

When all clear, it broadcasts a 5-minute warning via `shutdown -r +5` so logged-in users can save work, then reboots into the staged image. SSH session ends mid-window? The next poll catches it. Window expires with sessions still active? Skip until next firing.

```bash
sudo cache22-autoreboot enable --at 'daily 04:00'                # daily 4am check
sudo cache22-autoreboot enable --at 'Sun 03:00'                  # Sundays only
sudo cache22-autoreboot enable --at 'Thu,Sat 16:00' --window 1h  # Thu+Sat between 4-5pm
sudo cache22-autoreboot enable --at 'daily 03:00' --allow-active-sessions  # don't defer for users
sudo cache22-autoreboot disable
sudo cache22-autoreboot status
```

`--at` is required (auto-reboot is opt-in by configuration, not by default). Window defaults to 30 minutes.

### Inspecting a staged update

When an update is staged, login banners appear (SSH MOTD, interactive shell greeting, KDE desktop notification) telling you to reboot. Drill into what changed:

```bash
cache22-changelog        # full package-level diff between booted and staged
cache22-changelog --check # silent; exit 0 if there's anything staged (used by banners)
```

Output shows package additions, removals, and version bumps so you can decide whether the change is something you care about right now or can wait.

### Bare bootc-fetch timer (alternative to cache22-autoupdate)

If you'd rather use bootc's own upstream timer instead of cache22's wrapper:

```bash
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

Same fetch+stage behavior; doesn't run flatpak/distrobox, doesn't drop the pending-reboot banners, doesn't compose with `cache22-autoreboot` for window-based reboots. Use this if you want the absolute minimum.

### Pinning to a specific build

Every successful build pushes three tags per variant: `:rolling` (moves with each build — what `cache22-update` follows), `:YYYY-MM-DD` (per-day pointer; the latest build of that day wins if multiple succeed), and `:sha-<7chars>` (immutable per-commit pointer). So if a fresh upgrade breaks something, you can pin to a known-good day or commit:

```bash
# Pin to a specific date
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:2026-05-04

# Pin to a specific commit (find the SHA in the GitHub Actions run)
sudo cache22-rebase --image ghcr.io/cmspam/cache22-cachy-kde:sha-9065ce1
```

To go back to following the rolling stream after pinning:

```bash
sudo cache22-rebase --variant cachy-kde   # or whichever variant you're on
```

Browse available tags at <https://github.com/cmspam/cache22/pkgs/container/cache22-cachy-kde> (substitute your variant).

## Switching variants

Want to flip from `cachy-kde` to `arch-server` (or any other combination)? Use `cache22-rebase`:

```bash
sudo cache22-rebase                          # interactive picker
sudo cache22-rebase --variant cachy-server   # pick by id
sudo cache22-rebase --image ghcr.io/foo:bar  # arbitrary OCI ref
sudo cache22-rebase --reboot                 # reboot when done
```

Switches are atomic and reversible — the previous deployment stays available for rollback until your next upgrade.

## Day-to-day on an immutable OS

`/usr` is read-only — `pacman -S` will refuse. Three escape hatches, in order of preference:

1. **Flatpak** (Flathub pre-configured) for GUI apps. KDE variants ship with the Bazaar storefront.
2. **`cache22-shell`** drops you into a CachyOS distrobox container with full pacman + AUR access for ad-hoc CLI tools, dev environments, etc. Nothing you do inside affects the host.
3. **`sudo bootc usroverlay`** mounts an ephemeral writable overlay on `/usr` — you can `pacman -S` after this, but the changes are lost on reboot. Use it for testing only.

For persistent kernel command-line additions:

```bash
sudo cache22-karg add nvidia_drm.fbdev=1
sudo cache22-karg list
sudo cache22-karg remove nvidia_drm.fbdev
```

For TPM2 LUKS auto-unlock (binds to firmware + Secure Boot state, so kernel updates don't break unlock):

```bash
sudo cache22-encryption enroll /dev/nvme0n1p3
```

## Helpers reference

| Command | What it does |
| --- | --- |
| `cache22-update` | Recommended upgrade frontend — pull + stage + finalize, optional `--reboot` and `--app-updates`. |
| `cache22-rebase` | Switch variants or to any other bootc image. |
| `cache22-secureboot` | Manage MOK enrollment of the cache22 SB cert. `status`, `enroll` (queue + set BootNext to MokManager), `unenroll`. |
| `cache22-karg` | Manage persistent kernel command-line args. |
| `cache22-encryption` | TPM2 auto-unlock for LUKS volumes. |
| `cache22-shell` | Open a CachyOS distrobox container for non-immutable package work. |
| `cache22-healthcheck` | Runs your `/etc/cache22/healthcheck.d/required.d/` scripts 2 min after boot; auto-rollback after 3 bad boots. |
| `cache22-gamescope-mode` | (KDE only) Toggle SteamOS-style gamescope autologin. |

## Rolling your own

Want a cache22 with different packages, your own patched repo, different desktop, or just your own branding? Fork this repository and have at it. The whole pipeline runs in your GitHub Actions and pushes to your `ghcr.io` namespace — no infrastructure on my end is involved.

Steps:

1. **Fork on GitHub.** GitHub Actions activates automatically on the fork.
2. **Generate a Secure Boot signing key + cert** (skip if you don't care about SB):
   ```bash
   openssl req -newkey rsa:2048 -nodes -keyout sb.key -new -x509 \
       -sha256 -days 3650 -subj "/CN=your-name SB key/" -out sb.crt
   ```
3. **Add the private key as a repo secret.** Settings → Secrets and variables → Actions → New repository secret. Name: `SECUREBOOT_PRIVATE_KEY`. Value: paste the contents of `sb.key`.
4. **Commit the cert into the fork.** Replace both copies (must be identical content):
   - `system_files/common/usr/share/cache22/secureboot.crt` — baked into the image; the installer drops it on the target ESP as `/EFI/BOOT/sbcert.der` and feeds it to `mokutil --import`.
   - `secureboot.crt` at the repo root — baked into the live ISO's ESP for the MokManager "Enroll key from disk" fallback path.
5. **(Optional) change the MOK enrollment password.** `MOK_PASSWORD="cache22sb"` in `installer/cache22-install` is what users type at MokManager on first boot. Set your own if branding matters.
6. **Edit packages / system_files / Containerfile / variants.json** to taste. `packages/{cachy,arch}-{common,kde,server}.txt` is the package list, one per line. `system_files/common/` is the overlay applied on top of the base image.
7. **Push.** The image build runs automatically on changes under `Containerfile`, `packages/**`, `system_files/**`, `scripts/**`. Built images land at `ghcr.io/<your-github-username>/cache22-<variant>:rolling`.
8. **Install your fork** with the cache22 ISO using `--image ghcr.io/<your-github-username>/cache22-<variant>:rolling`, or from an existing cache22 install with `sudo cache22-rebase --image ghcr.io/<your-github-username>/cache22-<variant>:rolling`.

If you skip the SB key (steps 2–5), builds still succeed but the kernel images aren't signed — your fork's installs will fail shim verification under SB. Users will need to disable SB or boot a kernel signed by another trusted key. Everything else is unaffected.

For deeper changes (adding a whole new family like a GNOME variant, restructuring the build), see [`docs/IMAGE_BUILD.md`](docs/IMAGE_BUILD.md), [`docs/INSTALLER.md`](docs/INSTALLER.md), [`docs/SECUREBOOT.md`](docs/SECUREBOOT.md), and [`ARCHITECTURE.md`](ARCHITECTURE.md).

## License

Apache 2.0 for the build scripts and tooling. Packaged software keeps its own licenses.

## Acknowledgements

[CachyOS](https://cachyos.org/) for the base distro and v3-optimized packages. [bootc](https://github.com/bootc-dev/bootc) and the broader ostree/composefs ecosystem. [bootcrew/mono](https://github.com/bootcrew/mono) for path-finding bootc-on-Arch ideas. [Universal Blue](https://universal-blue.org/) and [Bazzite](https://bazzite.gg/) for the multi-variant Containerfile pattern.
