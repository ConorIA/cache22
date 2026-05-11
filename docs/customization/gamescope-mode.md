---
title: Gamescope Mode (SteamOS-style)
parent: Customization
nav_order: 5
---

# Gamescope Mode (SteamOS-style)

KDE variants of cache22 ship a gamescope-based "console mode" similar to SteamOS Big Picture. `cache22-gamescope-mode` toggles plasma autologin into a gamescope Wayland session that boots straight into Steam's Big Picture interface.

This is KDE-variant only (`cachy-kde` and `arch-kde`). The script and session files are not present on server variants.

## Synopsis

```
sudo cache22-gamescope-mode on        # Enable autologin into gamescope.
sudo cache22-gamescope-mode off       # Restore the regular plasma greeter.
cache22-gamescope-mode status         # Report current state.
```

## What it does

`on` writes `/etc/plasmalogin.conf.d/zz-cache22-gamescope-autologin.conf` with the autologin user (UID 1000) and `Session=gamescope-session.desktop`. The next reboot lands directly in gamescope, which auto-launches Steam.

`off` removes that config file (and clears the one-shot marker described below). The regular plasma greeter is back at next boot.

`status` reports whether the autologin config is present.

The script does NOT touch the gamescope session files themselves. Those ship in the image at `/usr/lib/cache22/gamescope/` and `/usr/share/wayland-sessions/gamescope-session.desktop`. They are always available to plasma; the script only controls whether autologin uses them.

## Examples

### Enable gamescope mode

```
$ sudo cache22-gamescope-mode on
[OK] Gamescope mode enabled (autologin = alice -> gamescope-session).

  Reboot to land in Steam Big Picture. Use Steam's power menu ->
  "Switch to Desktop" for a one-shot plasma session, or run
  'sudo cache22-gamescope-mode off' to turn this off permanently.
```

After reboot, the user is auto-logged-in to a gamescope session running Steam Big Picture. No plasma greeter, no manual login.

### Switch to desktop temporarily

From within Steam Big Picture, the power menu has a "Switch to Desktop" option. Selecting it logs out of gamescope and starts a one-shot plasma session.

After the user logs out of plasma (or reboots), the system returns to gamescope autologin.

This is implemented by `cache22-gamescope-restore.service`, a oneshot unit that runs at boot and re-applies the gamescope autologin if the marker file `/var/lib/cache22/gamescope-restore-on-next-boot` is present. Plasma's "Switch to Desktop" creates that marker. The cleanup happens on the boot after the marker has done its job.

### Permanently disable gamescope mode

```
$ sudo cache22-gamescope-mode off
[OK] Gamescope autologin removed; next boot uses the regular plasma greeter.
```

The system goes back to the regular plasma login screen on next boot.

### Check current state

```
$ cache22-gamescope-mode status
Gamescope mode: ON
  config: /etc/plasmalogin.conf.d/zz-cache22-gamescope-autologin.conf
    [Autologin]
    Session=gamescope-session.desktop
    User=alice
    Relogin=true
```

Or:

```
$ cache22-gamescope-mode status
Gamescope mode: OFF (no /etc/plasmalogin.conf.d/zz-cache22-gamescope-autologin.conf)
```

## What gets enabled in gamescope

The gamescope session that ships with cache22 runs:

1. `gamescope` as the Wayland compositor with Steam-friendly defaults.
2. `steam -bigpicture` (or `steam -gamepadui`) as the foreground client.
3. The user's home directory and Steam library are unchanged from regular plasma sessions.

Controllers, audio, network, and Steam Remote Play work the same as in plasma. This is just an alternate session, not a separate user account or container.

## Limitations

- The gamescope session is bare. It runs Steam and gives the user full SteamOS-Big-Picture-style controls within Steam, but does not provide window management for non-Steam apps.
- For non-Steam apps from inside gamescope, add them to Steam first (Add a Non-Steam Game) and they'll launch via Steam's overlay.
- Some plasma-specific features (KWin window management, plasma desktop widgets) are unavailable. Use "Switch to Desktop" to access plasma when needed.

## Files involved

| Path | Purpose |
|---|---|
| `/usr/bin/cache22-gamescope-mode` | The on/off/status script. |
| `/etc/plasmalogin.conf.d/zz-cache22-gamescope-autologin.conf` | The autologin config (created by `on`, removed by `off`). |
| `/usr/lib/cache22/gamescope/start-gamescope-session` | The gamescope session launcher. |
| `/usr/share/wayland-sessions/gamescope-session.desktop` | The session entry plasma sees. |
| `/var/lib/cache22/gamescope-restore-on-next-boot` | Marker for the one-shot plasma session, set by Steam's "Switch to Desktop". |
| `/usr/lib/systemd/system/cache22-gamescope-restore.service` | Re-applies gamescope autologin after the one-shot plasma session ends. |

## See also

- [Distrobox](../distrobox/) for installing CLI gaming tools (e.g., scummvm, retroarch CLI) outside the immutable host.
- [Flatpak](../flatpak/) for non-Steam GUI gaming apps (Lutris, Heroic Games Launcher).
