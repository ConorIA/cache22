---
title: Distrobox
parent: Customization
nav_order: 2
---

# Distrobox

`distrobox` runs container-based development environments tightly integrated with the host. Inside a distrobox, the user has full `pacman` (or apt, dnf, etc., depending on the chosen base image) access. Files in the user's home directory are shared with the host; processes are isolated.

cache22 ships `distrobox` and provides `cache22-shell` as a one-line entry into a CachyOS-based container.

## Quick start

```
cache22-shell
```

This opens a shell inside a distrobox container based on `cachyos/cachyos:latest`. From there, `pacman -S whatever` works, AUR helpers can be installed and used, and built binaries can be executed (the container's `/home` is the host's `/home`).

The first invocation creates the container (downloads the image, installs the user's profile). Subsequent invocations enter the existing container instantly.

## Why use it

- Install CLI tools that are not in cache22's package list.
- Use AUR packages.
- Run language-specific dev environments (rustup, nvm, pyenv) without polluting the host.
- Build and test software in a writable filesystem.
- Access tools from other distros (debian, fedora, ubuntu) on the same host.

## What survives across host reboots

- The container itself (lives in `/home/<user>/.local/share/distrobox/` or as a podman/docker volume).
- Files in `/home`, `/var/home`, `/root` (these are the same as on the host).
- Installed packages inside the container (the container's filesystem is persistent per-container).

What does NOT survive:

- Anything the container wrote to its own root filesystem if the container is deleted with `distrobox rm`.
- The container itself if `distrobox-host-exec` fails to find host services it expects.

## Examples

### Install an AUR package

```
cache22-shell
# Inside the container:
sudo pacman -S paru        # If not already there.
paru -S <aur-pkg>
```

The installed binary lives in the container. To use it from the host without entering the container, see "Exporting commands" below.

### Use a different base image

Create a debian-based distrobox alongside the cachy one:

```
distrobox create --name debian --image debian:trixie
distrobox enter debian
# Inside:
sudo apt update && sudo apt install <package>
```

`cache22-shell` is hard-coded to use the cachy container; for other distros, use `distrobox enter <name>` directly.

### Export a command from container to host

```
# Inside the container:
distrobox-export --bin /usr/bin/<command>
```

This creates a wrapper at `~/.local/bin/<command>` on the host. Running it from the host shell transparently runs the command inside the container.

For graphical apps:

```
# Inside the container:
distrobox-export --app <appname>
```

This creates a `.desktop` file on the host so the app appears in the application menu. Running it launches the app inside the container with display forwarding.

### Update all distroboxes from the host

```
distrobox upgrade --all
```

Runs `pacman -Syu` (or apt upgrade, etc., depending on the container distro) inside each distrobox. `cache22-update --app-updates` calls this after the OS update.

### List existing distroboxes

```
distrobox list
```

### Remove a distrobox

```
distrobox stop <name>
distrobox rm <name>
```

This deletes the container and its filesystem. Files in `/home` are preserved (those are the host's).

## distrobox-host-exec and flatpak

`distrobox-host-exec` runs a command on the host from inside a distrobox. It uses `host-spawn` (or `flatpak-spawn`) to talk to the host's session manager over DBus.

For this to work, the host needs `flatpak` installed because `host-spawn` connects to the `org.freedesktop.Flatpak` DBus service that flatpak's session-helper provides. Without flatpak, `distrobox-host-exec` returns nothing silently. See [#1198 in the distrobox repo](https://github.com/89luca89/distrobox/issues/1198) for the upstream context.

cache22 ships flatpak in all variants (server included) specifically so `distrobox-host-exec` works. If flatpak is removed, `distrobox-host-exec` breaks.

To call a host command from inside a distrobox:

```
# Inside the container:
distrobox-host-exec systemctl status sshd
distrobox-host-exec sudo bootc upgrade
```

The command runs as the host's user (whoever is running the container). For commands needing root on the host, prefix with `sudo`; the host's sudo prompt is what gates access.

## When NOT to use distrobox

- For GUI apps, prefer Flatpak (see [Flatpak](../flatpak/)). Flatpak is more sandboxed and integrates better with desktop services.
- For temporary `pacman` testing on the cache22 image itself (rather than a separate distro), use `bootc usroverlay` (see [usroverlay](../usroverlay/)). Note that usroverlay is per-boot; changes are discarded on reboot.
- For permanent additions to the cache22 image, fork the repo and add packages to `packages/*.txt`. See [Forking](../../building-and-forking/forking/).

## Configuration

cache22 ships no specific distrobox configuration. Defaults apply. To customize:

- `~/.config/distrobox/distrobox.conf` for user-specific settings (image, hooks, mount overrides).
- `~/.local/share/distrobox/<container-name>/` for per-container state.

See `man distrobox.conf` for the full list of settings.

## See also

- [Flatpak](../flatpak/) for the preferred way to run GUI apps.
- [usroverlay](../usroverlay/) for temporary writable `/usr` when distrobox is not appropriate.
- [Forking](../../building-and-forking/forking/) for permanent additions to the cache22 image.
