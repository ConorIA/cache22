---
title: Hyprland Session
parent: Customization
nav_order: 6
---

# Hyprland Session

The `cachy-hyprland` and `arch-hyprland` variants ship [Hyprland](https://hypr.land/) with a session built around it. Hyprland has no default desktop of its own, so cache22 supplies one: a bar, a launcher, a notification daemon, a lock screen, and a set of keybindings that work on first login. None of it is fixed in place. Everything below is a config file you can override from your home directory.

This page is about the parts cache22 chose. For what the options mean, the [Hyprland wiki](https://wiki.hypr.land/) is the reference.

## What is in the session

| Piece | Package | Notes |
| --- | --- | --- |
| Compositor | `hyprland` | Session entries for both plain Hyprland and `uwsm`. |
| Greeter | `plasma-login-manager` | The same greeter the KDE variants use. |
| Bar | `waybar` | Config in `/etc/xdg/waybar/`. |
| Launcher | `rofi` | `rofi -show drun`, bound to SUPER+R. |
| Notifications | `swaync` | Control center on SUPER+N. |
| Lock screen | `hyprlock` | Driven by `hypridle` and `loginctl lock-session`. |
| Idle | `hypridle` | Dim at 5 min, lock at 10, screen off at 15. |
| Wallpaper | `hyprpaper` | Points at `/usr/share/hypr/wall0.png`. |
| Terminal | `kitty` | SUPER+Q. |
| Files | `thunar` | With `gvfs`, `tumbler` thumbnails, archive plugin. |
| Screenshots | `hyprshot`, `grim`, `slurp`, `swappy` | SUPER+SHIFT+S for a region. |
| Clipboard history | `cliphist`, `wl-clipboard` | SUPER+W. |
| Portals | `xdg-desktop-portal-hyprland`, `-gtk` | Screen sharing and file dialogs. |
| Polkit agent | `hyprpolkitagent` | Started as a systemd user service. |
| Tray | `network-manager-applet`, `blueman` | Network and Bluetooth. |
| Displays | `nwg-displays` | GUI monitor layout, writes Hyprland monitor lines. |
| Theming | `nwg-look`, `qt5ct`, `qt6ct`, `kvantum` | GTK and Qt appearance. |

The gaming stack (Steam, Lutris, gamescope, MangoHud, Sunshine) and the NVIDIA driver are present, same as the other desktop variants. The SteamOS-style gamescope session switcher is not: it is coupled to KDE autologin. See [Gamescope Mode](../gamescope-mode/).

## Default keybindings

`SUPER` is the modifier.

| Keys | Action |
| --- | --- |
| SUPER+Q | Terminal |
| SUPER+E | File manager |
| SUPER+B | Browser |
| SUPER+R | Launcher |
| SUPER+C | Close window |
| SUPER+M | Exit Hyprland |
| SUPER+V | Toggle floating |
| SUPER+F | Fullscreen |
| SUPER+P | Pseudotile |
| SUPER+J | Toggle split direction |
| SUPER+L | Lock screen |
| SUPER+N | Notification center |
| SUPER+W | Clipboard history |
| SUPER+SHIFT+S | Screenshot a region to the clipboard |
| Print | Screenshot the whole output |
| SUPER+arrows | Move focus |
| SUPER+SHIFT+arrows | Move the window |
| SUPER+1..0 | Switch workspace |
| SUPER+SHIFT+1..0 | Send window to workspace |
| SUPER+S | Toggle the scratchpad workspace |
| SUPER+ALT+S | Send window to the scratchpad |
| SUPER+drag | Move (left button) or resize (right button) |

Volume, brightness, and media keys are bound to `wpctl`, `brightnessctl`, and `playerctl`.

## Making it yours

`/usr` is read-only, but none of the session config lives there. Hyprland and its tools search `$XDG_CONFIG_HOME/hypr/`, then `~/.config/hypr/`, then `/etc/xdg/hypr/`, and stop at the first file they find. cache22 ships the last one, so anything you put in your home directory wins:

```
mkdir -p ~/.config/hypr
cp /etc/xdg/hypr/hyprland.conf ~/.config/hypr/
```

Edit, then reload with `hyprctl reload`. The same applies to `hypridle.conf`, `hyprlock.conf`, and `hyprpaper.conf`.

Waybar works the same way, from `/etc/xdg/waybar/` to `~/.config/waybar/`:

```
mkdir -p ~/.config/waybar
cp /etc/xdg/waybar/config.jsonc /etc/xdg/waybar/style.css ~/.config/waybar/
```

Two things worth knowing:

- Hyprland reads `hyprland.lua` as well as `hyprland.conf`, and a Lua config found anywhere in the search path beats a `.conf` found anywhere. cache22 ships `.conf`. If you write a Lua config, it takes over completely; do not expect the two to merge.
- Hyprland does not run XDG autostart entries (`/etc/xdg/autostart/*.desktop`). Anything that would normally start that way, including the tray applets and fcitx5, is launched by `exec-once` lines in `hyprland.conf`. If you replace the file with your own, carry those lines across or those pieces will not start.

Whole dotfile collections (HyDE, end-4, ML4W and so on) install into `~/.config` and work here as they do on any Arch system. They may expect packages the image does not carry; a Flatpak or a [Distrobox](../distrobox/) container covers most of that. Baking extra packages into the image itself means [forking](../../building-and-forking/forking/).

## Keyboard layout

The config sets `kb_layout = us`. Hyprland does not read the console or X11 keymap, so change it in your own copy of `hyprland.conf`:

```
input {
    kb_layout = de
    # or several, with a switch key:
    # kb_layout = us,ru
    # kb_options = grp:alt_shift_toggle
}
```

## Session entries at the greeter

Two Hyprland entries appear in the greeter's session list:

- **Hyprland.** The compositor started directly.
- **Hyprland (uwsm-managed).** Started through [uwsm](https://github.com/Vladimir-csp/uwsm), which puts the session under the systemd user manager so `graphical-session.target` and user units behave the way they do on a full desktop environment.

Both use the same `hyprland.conf`. The plain entry is the tested default; uwsm is there for people who want the systemd integration.

## Suspend

`hypridle` dims, locks, and blanks the screen, but does not suspend. cache22 runs on servers, laptops, and desktops from one image, and an unwanted suspend on a machine doing work is worse than a screen that stays on. Add it yourself in `~/.config/hypr/hypridle.conf`:

```
listener {
    timeout    = 1800
    on-timeout = systemctl suspend
}
```
