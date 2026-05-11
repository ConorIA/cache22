---
title: Customization
nav_order: 5
has_children: true
permalink: /customization/
---

# Customization

cache22 is immutable. `/usr` is read-only and `pacman -S` will refuse. This section covers the supported ways to add software, change configuration, and run development environments.

In rough order of preference:

1. **[Flatpak](./flatpak/).** GUI applications with no impact on the base system. KDE variants ship the Bazaar storefront preconfigured.
2. **[Distrobox](./distrobox/).** A full container (CachyOS, Arch, Fedora, Ubuntu, Debian, Alpine, openSUSE, Rocky, or Alma) with native package management. Use for CLI tools, dev environments, and packages not appropriate for Flatpak.
3. **[Kernel Args](./kernel-args/).** Persistent kernel command-line options via `cache22-karg` and `/etc/cache22/extra-cmdline`.
4. **[bootc usroverlay](./usroverlay/).** Temporary writable `/usr` for testing only. Discarded on reboot.
5. **[Gamescope Mode](./gamescope-mode/).** SteamOS-style autologin into a gamescope session running Steam Big Picture. KDE variants only.

For more invasive changes (additional packages baked into the image, custom system files, additional variants), fork the repository: see [Building and Forking](../building-and-forking/).
