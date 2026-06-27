---
title: Kernel Args
parent: Customization
nav_order: 1
---

# Kernel Args

cache22 stores per-machine kernel command-line arguments in `/etc/cache22/extra-cmdline`. The arguments are concatenated with image-default kargs (from `/usr/lib/bootc/kargs.d/*.toml` in the image) and baked into the signed UKI's `.cmdline` PE section by `resign-uki`.

`cache22-karg` is the recommended interface for adding, removing, and listing per-machine kargs.

## Synopsis

```
sudo cache22-karg list
sudo cache22-karg add <karg>
sudo cache22-karg remove <key>
sudo cache22-karg reset
```

## extra-cmdline format

`/etc/cache22/extra-cmdline` is a plain-text file with one karg per line. Lines starting with `#` are comments. Blank lines are ignored.

Example after a fresh install:

```
# Per-machine kargs written by cache22-install.
rd.luks.uuid=1ba5a644-d061-4ef2-b0c1-21e84af7585e
rd.luks.name=1ba5a644-d061-4ef2-b0c1-21e84af7585e=cache22-root
rd.luks.options=1ba5a644-d061-4ef2-b0c1-21e84af7585e=discard,tpm2-device=auto
rootflags=subvol=root,compress=zstd:1,noatime,space_cache=v2,discard=async
```

These define how the initramfs unlocks LUKS, names the dm-crypt mapper, and mounts the btrfs root with the right subvol and options. They are essential for boot. Do not remove them.

## When edits take effect

When `/etc/cache22/extra-cmdline` is modified, `cache22-resign-uki.path` triggers `cache22-resign-uki.service` automatically. The service rebuilds UKIs for all live deploys with the new cmdline. The next reboot picks up the new UKI.

To force an immediate rebuild without waiting for the path watcher (rare; the watcher is reliable):

```
sudo systemctl start cache22-resign-uki.service
```

To verify the rebuild ran:

```
sudo systemctl status cache22-resign-uki.service
```

## Examples

### List current kargs

```
sudo cache22-karg list
```

Shows the contents of `/etc/cache22/extra-cmdline` minus comments.

### Add a kernel arg

Force an Intel iGPU into a specific mode for kexec compatibility:

```
sudo cache22-karg add i915.modeset=1
```

Enable verbose kernel logging:

```
sudo cache22-karg add loglevel=8
sudo cache22-karg add debug
```

Enable a serial console (for headless debugging):

```
sudo cache22-karg add console=tty1
sudo cache22-karg add console=ttyS0,115200
```

The order of `console=` arguments matters; the last one is the system console. If serial fallback is the goal:

```
sudo cache22-karg add console=tty1
sudo cache22-karg add console=ttyS0,115200
```

This sets tty1 as the system console with serial as a fallback for output.

### Remove a kernel arg

By key (matches `key=value` or just `key`):

```
sudo cache22-karg remove debug
sudo cache22-karg remove loglevel
```

The remove is by key, not value. So `cache22-karg remove console` removes ALL `console=` entries.

### Reset to install-time defaults

Remove all user-added kargs, leaving only the install-time entries:

```
sudo cache22-karg reset
```

This rewrites `/etc/cache22/extra-cmdline` to the original cache22-install output. Useful for recovery if the file was corrupted by manual edits.

### Manual edit

```
sudo nano /etc/cache22/extra-cmdline
```

After saving, `cache22-resign-uki.path` triggers a rebuild. Verify with:

```
sudo systemctl status cache22-resign-uki.service
```

If the rebuild errored, the previous UKIs remain in place; the system continues to boot with the prior cmdline. Check the journal:

```
sudo journalctl -u cache22-resign-uki.service -b
```

## What kargs are baked into the UKI

The UKI's `.cmdline` is the concatenation of:

1. **Image-default kargs** from `/usr/lib/bootc/kargs.d/*.toml` in the deploy. These are common kargs the image author chose for all installs.
2. **Per-machine kargs** from `/etc/cache22/extra-cmdline`. These are install-specific.
3. **The ostree= argument** that points to the deploy directory. Added by `resign-uki` automatically.

To see the actual cmdline a built UKI carries:

```
sudo objcopy -O binary --only-section=.cmdline \
    /efi/EFI/Linux/cache22-<csum>.efi /dev/stdout
```

Or read it from `/proc/cmdline` for the currently-booted kernel:

```
cat /proc/cmdline
```

## Common kargs to know about

| Karg | Effect |
|---|---|
| `quiet` | Suppress most kernel boot messages. Default in cache22. |
| `splash` | Show plymouth splash screen. Default on KDE variants. |
| `loglevel=8` | Maximum kernel logging verbosity. |
| `debug` | Enable debug-level kernel messages. |
| `nomodeset` | Disable KMS. Falls back to firmware framebuffer. Useful for video debugging. |
| `i915.modeset=0` / `amdgpu.modeset=0` / `nouveau.modeset=0` | Disable KMS for a specific driver. |
| `module_blacklist=foo,bar` | Prevent named modules from loading. |
| `console=ttyS0,115200` | Add serial console. |
| `nokaslr` | Disable kernel address space layout randomization. Sometimes helps debugging. |
| `init=/bin/sh` | Boot directly to a shell instead of systemd. Recovery only; bypasses normal init. |

For the full list of available kargs, see the [kernel-parameters.txt](https://docs.kernel.org/admin-guide/kernel-parameters.html) documentation.

## What if a bad karg breaks the boot

If the system fails to boot with a new karg:

1. At the sd-boot menu, select the previous deploy (rollback). The previous deploy's UKI has the old cmdline.
2. Boot. Edit `/etc/cache22/extra-cmdline` to remove the bad karg.
3. The path watcher rebuilds UKIs for the current (now-rollback) deploy and the failed deploy.
4. Reboot into the now-fixed deploy.

If both deploys' UKIs have the bad karg (rare; only happens if the karg was added without rebooting between deploys):

1. Boot the live ISO.
2. Run `cache22-repair` (see [Repair](../../system-ops/repair/)).
3. From the repair shell, edit `/etc/cache22/extra-cmdline` and trigger a UKI rebuild.

## See also

- [Boot Chain](../../boot-and-security/boot-chain/) for how UKIs are signed and loaded.
- [Per-Deploy UKI Build](../../architecture/per-deploy-uki/) for the resign-uki internals.
- [Three Reboot Paths](../../updates-and-reboots/three-reboot-paths/) for what kexec needs from the UKI.
