---
title: Flatpak
parent: Customization
nav_order: 3
---

# Flatpak

cache22 ships `flatpak` in all variants. KDE variants additionally include the [Bazaar](https://github.com/kolunmi/bazaar) Flatpak storefront for browsing and installing apps.

Flatpak is the recommended way to install GUI applications on cache22. The applications run in their own sandboxed environments, do not modify `/usr`, and update independently of the OS image.

## Installing an app

Via Bazaar (KDE variants): launch Bazaar from the application menu, search, click Install.

Via the command line:

```
flatpak install flathub org.mozilla.firefox
flatpak install flathub com.discordapp.Discord
flatpak install flathub org.libreoffice.LibreOffice
```

The first install per Flathub remote prompts to add the remote. cache22's Flathub configuration is preinstalled; the prompt should not appear.

To install for the system (all users) instead of the current user:

```
sudo flatpak install --system flathub org.mozilla.firefox
```

Default install location is per-user (`~/.local/share/flatpak/`). System-wide installs go to `/var/lib/flatpak/`.

## Listing and updating

```
flatpak list                       # All installed apps + runtimes.
flatpak list --app                 # Apps only.
flatpak update                     # Update all installed apps + runtimes.
flatpak update org.mozilla.firefox # Update one app.
```

`cache22-update --app-updates` runs `flatpak update -y` for the user who invoked sudo, in addition to the OS update.

## Running

```
flatpak run org.mozilla.firefox
```

Or use the desktop entry that flatpak installs in the application menu.

## Removing

```
flatpak uninstall org.mozilla.firefox
flatpak uninstall --unused          # Remove unused runtimes.
```

## Sandbox permissions

Each Flatpak app declares the sandbox permissions it needs (filesystem access, network, devices). To inspect what an app has access to:

```
flatpak info --show-permissions org.mozilla.firefox
```

To override permissions per-app:

```
flatpak override --user --filesystem=home org.mozilla.firefox       # Grant home access.
flatpak override --user --nosocket=wayland org.mozilla.firefox      # Block Wayland (force XWayland).
flatpak override --user --reset org.mozilla.firefox                 # Reset overrides.
```

System-wide overrides use `--system` instead of `--user` and require root.

For GUI inspection of permissions, [Flatseal](https://github.com/tchx84/Flatseal) (also a Flatpak) provides a per-app permissions editor.

## Other remotes

Flathub is the only remote configured by default. To add others:

```
flatpak remote-add --if-not-exists <name> <url>
```

Common alternatives:

- [GNOME Nightly](https://wiki.gnome.org/Apps/Nightly).
- [KDE Nightly](https://userbase.kde.org/Tutorials/Flatpak#KDE_Apps).
- Vendor-specific remotes (some apps publish their own).

## Bazaar storefront (KDE variants)

Bazaar provides a graphical storefront UI:

- Browse Flathub by category.
- Search apps.
- See app screenshots, descriptions, and ratings.
- Install / update / uninstall.

Launch from the KDE application menu. Bazaar replaces GNOME Software / KDE Discover in cache22's KDE setup.

## When to use Flatpak vs Distrobox vs usroverlay

| Use case | Best tool |
|---|---|
| GUI desktop apps (Firefox, Discord, LibreOffice, etc.) | Flatpak |
| CLI tools, dev environments, AUR packages | [Distrobox](../distrobox/) |
| Testing a one-off `pacman -S` change to cache22 itself | [usroverlay](../usroverlay/) (discarded on reboot) |
| Permanent additions to cache22 | [Fork the repo](../../building-and-forking/forking/) |

## See also

- [Distrobox](../distrobox/) for CLI tools and dev environments.
- [Forking](../../building-and-forking/forking/) for permanent additions.
