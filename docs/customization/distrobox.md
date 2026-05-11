---
title: Distrobox
parent: Customization
nav_order: 2
---

# Distrobox

`distrobox` runs container-based development environments tightly integrated with the host. Inside a distrobox, the user has full package-manager access (`pacman`, `dnf`, `apt`, `apk`, etc., depending on the chosen base distro). Files in the user's home directory are shared with the host. Processes are isolated.

cache22 ships `distrobox` and `cache22-shell`, a frontend that handles distro selection, per-container state, and switching between containers.

## cache22-shell

`cache22-shell` is the recommended entry point. On first launch it presents a picker of pre-configured distros, creates a container of the chosen flavour, and remembers the choice for subsequent invocations.

### Supported distros

| Id | Distro | OCI image |
|---|---|---|
| `cachyos` | CachyOS v3 (x86-64-v3 builds) | `docker.io/cachyos/cachyos-v3:latest` |
| `arch` | Arch Linux | `docker.io/library/archlinux:latest` |
| `fedora` | Fedora (toolbox) | `registry.fedoraproject.org/fedora-toolbox:latest` |
| `ubuntu` | Ubuntu LTS | `docker.io/library/ubuntu:latest` |
| `debian` | Debian stable | `docker.io/library/debian:stable` |
| `alpine` | Alpine Linux | `docker.io/library/alpine:latest` |
| `opensuse` | openSUSE Tumbleweed | `registry.opensuse.org/opensuse/distrobox:latest` |
| `rocky` | Rocky Linux | `quay.io/toolbx-images/rockylinux-toolbox:latest` |
| `alma` | AlmaLinux | `quay.io/toolbx-images/almalinux-toolbox:latest` |

CachyOS is the default because it matches the host's x86-64-v3 build target. If the CachyOS mirrors are slow on a given network path, pick another distro from the picker.

### Synopsis

```
cache22-shell                    # Enter active container (or pick on first run).
cache22-shell --new              # Show picker even if a container already exists.
cache22-shell --switch           # Pick a different existing container as active.
cache22-shell --list             # List all cache22-shell-managed containers.
cache22-shell --remove           # Delete the active container.
cache22-shell --help
```

### State

`cache22-shell` records the active container name in `~/.config/cache22-shell/active`. All managed containers are named `cache22-<distro-id>` (e.g., `cache22-cachyos`, `cache22-fedora`). Multiple containers can coexist; `--switch` chooses which one is active.

### First launch

```
$ cache22-shell

  cache22-shell - pick a distro for your container
  (each is a separate distrobox; you can have several side by side)

    1) CachyOS v3 (x86-64-v3 builds)
    2) Arch Linux
    3) Fedora (toolbox)
    4) Ubuntu LTS
    5) Debian stable
    6) Alpine Linux
    7) openSUSE Tumbleweed
    8) Rocky Linux
    9) AlmaLinux

    q) cancel

  [1] >
```

Bare Enter selects the default (CachyOS). Type a number to pick another. Type `q` to cancel.

After selection, the container is created (~30 seconds for the first time, since the image is pulled). Subsequent invocations enter the existing container instantly.

### Examples

#### Enter the active container

```
cache22-shell
```

If no active container exists, the picker appears. Otherwise, the active container is entered immediately.

#### Run a single command in the active container without entering an interactive shell

```
cache22-shell pacman -Qi pacman
cache22-shell ls -la
```

Arguments after `cache22-shell` (other than the named subcommands) are passed through as the command to run inside the container.

#### Create another container alongside the active one

```
cache22-shell --new
# Pick a different distro from the picker.
```

The newly-created container becomes the active one. The previous container still exists; switch back with `--switch`.

#### List all containers

```
$ cache22-shell --list
Active container: cache22-cachyos

All cache22-shell containers:
  cache22-cachyos
  cache22-fedora
  cache22-debian
```

#### Switch active container

```
$ cache22-shell --switch

  Existing cache22-shell containers:
    1) cache22-cachyos
    2) cache22-fedora
    3) cache22-debian

  Make active > 2
  active: cache22-fedora
```

#### Remove the active container

```
$ cache22-shell --remove
About to remove distrobox container: cache22-fedora
Confirm? [y/N] y
```

The container's filesystem is deleted. Files in `/home` are preserved (they live on the host).

#### Use a custom image

```
CACHE22_SHELL_IMAGE=quay.io/toolbx-images/centos-stream-toolbox:latest cache22-shell
```

Bypasses the picker. Container name defaults to `cache22-custom` (override with `CACHE22_SHELL_NAME=...`).

## Inside the container

Once inside, install packages with the container distro's native tools:

```
# CachyOS / Arch
sudo pacman -S <package>
paru -S <aur-package>     # paru pre-installed on CachyOS image; install on plain Arch.

# Fedora
sudo dnf install <package>

# Ubuntu / Debian
sudo apt update
sudo apt install <package>

# Alpine
sudo apk add <package>

# openSUSE
sudo zypper install <package>
```

Files in `/home` are shared with the host. Builds and config land in the host's home dir. Processes are isolated; the container has its own PID namespace, network namespace (typically host-shared though), and mount namespace.

## Exporting commands and apps

`distrobox-export` makes container-installed commands runnable from the host shell or makes container-installed apps appear in the host's application menu.

### Export a CLI command

```
# Inside the container:
distrobox-export --bin /usr/bin/<command>
```

Creates a wrapper at `~/.local/bin/<command>` on the host. Running it transparently runs the container command.

### Export a graphical app

```
# Inside the container:
distrobox-export --app <appname>
```

Creates a `.desktop` file on the host so the app appears in the application menu. Launching it runs the app in the container with display forwarding.

## distrobox-host-exec and the flatpak dependency

`distrobox-host-exec` runs a command on the host from inside a container. It uses `host-spawn` (or `flatpak-spawn`) to talk to the host's session manager over DBus.

For this to work, the host needs `flatpak` installed. `host-spawn` connects to the `org.freedesktop.Flatpak` DBus service that flatpak's session-helper provides. Without flatpak, `distrobox-host-exec` returns nothing silently. See [#1198 in the distrobox repo](https://github.com/89luca89/distrobox/issues/1198) for the upstream context.

cache22 ships `flatpak` in all variants (server included) so `distrobox-host-exec` works out of the box. Removing `flatpak` would break it.

```
# Inside the container:
distrobox-host-exec systemctl status sshd
distrobox-host-exec sudo bootc upgrade
```

Commands run as the host user (whoever launched the container). `sudo` prompts gate access on the host side.

## Updating containers

```
distrobox upgrade --all
```

Runs the container distro's upgrade command (`pacman -Syu`, `dnf update`, etc.) inside each distrobox.

`cache22-update --app-updates` calls `distrobox upgrade --all` after the OS update.

## Direct distrobox commands

`cache22-shell` is a thin frontend over `distrobox`. The full distrobox CLI is also available:

```
distrobox list                   # All containers, not just cache22-shell-managed.
distrobox enter <name>           # Enter any container by name.
distrobox create --name foo --image <image>
distrobox stop <name>
distrobox rm <name>
```

`cache22-shell --list` shows only containers named `cache22-*` (the ones it manages). Containers created with `distrobox create` directly are not picked up by `cache22-shell --switch` unless renamed to start with `cache22-`.

## When NOT to use distrobox

- For GUI apps, prefer Flatpak (see [Flatpak](../flatpak/)). Flatpak is more sandboxed and integrates better with desktop services.
- For temporary `pacman` testing on the cache22 host itself, use `bootc usroverlay` (see [usroverlay](../usroverlay/)). Note that usroverlay is per-boot; changes are discarded on reboot.
- For permanent additions to the cache22 image, fork the repo and add packages to `packages/*.txt`. See [Forking](../../building-and-forking/forking/).

## Configuration

`cache22-shell` state lives in:

| Path | Content |
|---|---|
| `~/.config/cache22-shell/active` | Name of the currently-active container. |

The containers themselves live wherever distrobox stores them (typically `~/.local/share/containers/storage/` for podman-backed distroboxes).

For per-distrobox advanced configuration (mounts, hooks, image overrides) edit `~/.config/distrobox/distrobox.conf`. See `man distrobox.conf` for the full list of settings.

## See also

- [Flatpak](../flatpak/) for the preferred way to run GUI apps.
- [usroverlay](../usroverlay/) for temporary writable `/usr` when distrobox is not appropriate.
- [Forking](../../building-and-forking/forking/) for permanent additions to the cache22 image.
