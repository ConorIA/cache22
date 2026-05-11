---
title: bootc usroverlay
parent: Customization
nav_order: 4
---

# bootc usroverlay

`/usr` is read-only on cache22. `pacman -S` will refuse with `error: failed to commit transaction (unable to lock database)` or similar.

`bootc usroverlay` mounts an ephemeral writable overlay on `/usr`. After running it, `pacman -S` works, files in `/usr` can be modified, and tools that expect to write to `/usr/local`, `/usr/lib`, etc., function normally.

**All changes to `/usr` are lost on the next reboot.** The overlay's upper directory lives in tmpfs.

## Synopsis

```
sudo bootc usroverlay
```

Idempotent. Subsequent invocations report that the overlay is already active.

## When to use it

- Testing a one-off `pacman -S <package>` to see if a package works on cache22 before deciding to add it permanently.
- Quickly debugging a system tool by editing its source in `/usr/lib`.
- Replacing a binary in `/usr/bin` to test a patched version.
- Installing a kernel module via `dkms` for ad-hoc testing (the module survives only until reboot).

## When NOT to use it

- For permanent additions: fork the cache22 repo, add to `packages/*.txt` (or `system_files/`), and rebuild. See [Forking](../../building-and-forking/forking/).
- For GUI apps: use [Flatpak](../flatpak/).
- For CLI tools and dev environments: use [Distrobox](../distrobox/).
- For per-machine kernel parameters: use [`cache22-karg`](../kernel-args/).

## What survives a reboot

Nothing in `/usr`. The overlay's upper dir is tmpfs.

What persists:
- Files in `/etc` (cache22 has `/etc` as a writable bind on the deploy's etc; persists per-deploy).
- Files in `/var` and `/home` (per-stateroot, persists across all deploys).

## Examples

### Try a package before adopting it

```
sudo bootc usroverlay
sudo pacman -S htop-vim
htop-vim                       # Try it out.
# Decide it is useful. Reboot to discard the overlay.
sudo systemctl reboot
# After reboot, htop-vim is gone.
# Fork the repo, add htop-vim to packages/*.txt, rebuild image.
```

### Edit a system script in place

```
sudo bootc usroverlay
sudo nano /usr/bin/cache22-update     # Make a quick fix.
sudo cache22-update                    # Test the fix.
# Discarded on reboot. Make the fix permanent by editing in the cache22 repo.
```

### Install a development version of a tool

```
sudo bootc usroverlay
git clone https://github.com/foo/bar.git /tmp/bar
cd /tmp/bar
make install PREFIX=/usr/local         # Or wherever.
# Use the tool. Discarded on reboot.
```

For a permanent dev environment with full toolchain access, prefer [Distrobox](../distrobox/) instead of usroverlay.

### Verify the overlay is active

```
mount | grep "on /usr "
```

When the overlay is active, the output shows `overlay on /usr type overlay (...)`. Without the overlay, `/usr` is part of the deploy's read-only mount.

## What about /etc, /var, /home

`/etc` is writable by default on cache22. No overlay needed for `/etc/` edits.

`/var` and `/home` are persistent per-stateroot. Edits survive across deploys.

`bootc usroverlay` only affects `/usr` and `/opt` (which is also read-only on bootc systems by default).

## Limitations

- Cannot install kernel modules for the running kernel that need to persist (modules need to be in the deploy's `/usr/lib/modules/<kver>/extra/`, which the overlay does not survive).
- Cannot persist sd-boot or UKI changes (those live on the ESP, not `/usr`).
- Overlay is per-running-system. After `systemctl reboot`, the next boot starts with no overlay.

## Recovery from a broken overlay

If the overlay is in a bad state:

```
sudo systemctl reboot
```

The overlay is discarded; `/usr` returns to the deploy's read-only state.

For any state that survives reboot (e.g., bootloader changes that broke the system), use the live ISO and `cache22-repair`. See [Repair](../../system-ops/repair/).

## See also

- [Distrobox](../distrobox/) for persistent CLI development environments.
- [Flatpak](../flatpak/) for GUI app installs.
- [Forking](../../building-and-forking/forking/) for permanent OS changes.
