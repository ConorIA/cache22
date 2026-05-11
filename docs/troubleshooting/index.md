---
title: Troubleshooting
nav_order: 9
permalink: /troubleshooting/
---

# Troubleshooting

Symptoms and solutions for common cache22 problems. Search this page for keywords matching the symptom.

## Boot

### After kexec, screen is blank

**Symptom:** Triggered `cache22-reboot --kexec` (or autoreboot fired with `KERNEL_CHANGE_STRATEGY=kexec`). Machine appears to boot but stays at a blank screen indefinitely. No login prompt, no graphical session, no apparent activity.

**Cause:** Two compounding issues:

1. The new kernel's KMS driver (amdgpu, i915, nouveau, nvidia) is not gracefully recovering the GPU from the state the previous kernel left it in. Without firmware GOP handover or POST, KMS stays uninitialized until plymouth or the display manager kicks in much later. The screen stays blank in early boot.
2. If LUKS is configured for TPM2 auto-unlock with a PCR 11 keyslot only (the default from `cache22-encryption enroll`), the LUKS prompt appears in early boot. The kexec'd boot bypasses sd-stub, so PCR 11 doesn't reach any signed prediction; TPM unseal fails; the kernel falls through to the LUKS passphrase prompt.
3. The user is sitting at an invisible passphrase prompt that the GPU cannot display.

**Fix:** Enroll a PCR 7 fallback keyslot so kexec auto-unlocks LUKS:

```
sudo cache22-encryption remove /dev/<luks-dev>
sudo cache22-encryption enroll /dev/<luks-dev>
# Answer 'y' to the PCR 7 fallback prompt.
```

After this, kexec'd boots auto-unlock LUKS via PCR 7. The blank-screen window is shorter (only until plymouth comes up), and the system reaches the login screen without manual input.

See [TPM and LUKS](../boot-and-security/tpm-luks/) for the security tradeoff of the PCR 7 fallback.

If the user does not want PCR 7 enrolled, alternative options:

- **Add a serial console** so the LUKS prompt is visible on a different output:

  ```
  sudo cache22-karg add console=tty1
  sudo cache22-karg add console=ttyS0,115200
  ```

  Then connect a serial cable (or use IPMI/iLO serial-over-LAN). The LUKS prompt appears on the serial console even when the GPU is dark.

- **Type the passphrase blindly.** The prompt is waiting for input. Type the passphrase and press Enter; if correct, boot continues. The screen comes alive after KMS recovers (the "mode change" the user notices later).

- **Do not use kexec.** Set `KERNEL_CHANGE_STRATEGY=hard` in `/etc/cache22/reboot.conf`. Full reboots through firmware POST initialize the GPU normally.

### Boot failed and rolled back automatically

**Symptom:** After an upgrade, the system rebooted, ran for a couple minutes, then rebooted again. Now running on the previous deploy.

**Cause:** `cache22-healthcheck` ran 2 minutes after boot and detected the failure. After 3 consecutive failed boots, it called `bootc rollback && systemctl reboot`.

**Investigation:**

```
sudo journalctl -b -1 -u cache22-healthcheck.service     # Last boot's check.
sudo journalctl -b -2 -u cache22-healthcheck.service     # Two boots ago.
```

The journal shows which check failed. Common failures:

- `01-system-running` failed because a service was stuck. Check `systemctl --failed` from the rolled-back deploy.
- `02-network` failed because NetworkManager was not running. Check `systemctl status NetworkManager`.
- A custom check in `/etc/cache22/healthcheck.d/required.d/` failed.

To re-attempt the failed deploy after diagnosing:

```
sudo bootc rollback         # Flips back to the deploy that failed.
sudo cache22-reboot
```

### Live ISO boots but won't enroll Secure Boot keys

**Symptom:** After installing cache22 from the live ISO and rebooting, `cache22-secureboot status` reports "Secure Boot: Disabled" or "Setup mode: Yes (not enrolled)".

**Cause:** sd-boot only enrolls keys when the firmware is in setup mode. If the firmware was not in setup mode at first boot, the auto-enroll files at `/efi/loader/keys/auto/` are ignored.

**Fix:**

1. Reboot into firmware setup (typically F2, DEL, F10, or ESC at power-on).
2. Either disable Secure Boot, or find the option to "Reset to Setup Mode" / "Clear Secure Boot Keys" / "Erase Platform Key".
3. Save and exit. Boot.
4. On the next boot, sd-boot detects setup mode and enrolls cache22's keys + Microsoft DB keys.

See [First-Boot Secure Boot Setup](../getting-started/secure-boot-first-boot/) for the full procedure with vendor-specific guidance.

### After cache22-secureboot rotate-keys, system won't boot

**Symptom:** After running `cache22-secureboot rotate-keys`, the firmware does not boot the cache22 UKI. May show "Secure Boot violation" or similar.

**Cause:** `rotate-keys` re-signs UKIs with the new SB key, but the firmware still has the OLD key enrolled. The new UKI signature does not verify against the old key.

**Fix:** Put the firmware back in setup mode and let sd-boot re-enroll the new keys:

1. Reboot into firmware setup.
2. Disable Secure Boot (or "Reset to Setup Mode").
3. Save and exit. Boot.
4. sd-boot detects setup mode and enrolls the new keys (auto-enroll files were regenerated by `rotate-keys`).
5. After this boot, re-enroll TPM2 LUKS keyslots since rotate-keys also changed the TPM PCR-policy key:

   ```
   sudo cache22-encryption remove /dev/<luks-dev>
   sudo cache22-encryption enroll /dev/<luks-dev>
   ```

## Updates

### MOTD says "update is staged" but `cache22-changelog` shows nothing

**Symptom:** SSH login banner or shell greeting reports a pending update. `cache22-changelog --check` exits 1 (no staged) or `bootc status .status.staged` is null.

**Cause:** Stale `/run/motd.d/10-cache22-pending-reboot` marker file. On older cache22 images, this file persisted across soft-reboots because `/run` survives soft-reboot by design.

**Fix:** Update to the latest cache22 image. Newer images include `cache22-pending-motd.service` which refreshes the marker on every boot and on every bootc state change.

For an immediate cleanup without waiting for the new image:

```
sudo rm /run/motd.d/10-cache22-pending-reboot
```

This is harmless. The marker is recreated automatically on the next bootc operation that actually stages a deploy.

### `bootc upgrade` re-stages the same image daily

**Symptom:** Every morning, `cache22-autoupdate` runs and the journal shows the same digest being re-staged with no actual changes.

**Cause:** Old behavior of bootc: even when the registry has no new content, `bootc upgrade` would re-stage the matching image. Newer cache22 images use `bootc upgrade --check` first to skip the redundant work.

**Fix:** Update to the latest cache22 image. `cache22-update` now checks before pulling.

For users on bare `bootc upgrade` (not via `cache22-update`), the redundant restage still happens. Use `cache22-update` instead.

### `cache22-update` exits with "Already up to date" but I want it to re-stage

**Symptom:** Want to force a re-stage of the current `:rolling` for testing.

**Cause:** `cache22-update` skips when `bootc upgrade --check` reports no changes.

**Fix:** Bypass `cache22-update` and call bootc directly:

```
sudo bootc upgrade
```

bootc will re-stage the image even when there is nothing new. Useful for testing the soft-reboot path with a guaranteed soft-reboot-capable staged deploy:

```
sudo bootc upgrade
sudo cache22-reboot     # Will soft-reboot since same kernel.
```

### Soft-reboot did not apply the update

**Symptom:** Ran `cache22-reboot --soft` (or auto-pick chose soft). Command completed but the system seems to be on the old deploy still.

**Investigation:**

```
findmnt /
```

If the source path includes the new deploy's csum (different from before), soft-reboot succeeded. If not, it didn't.

Other checks:

```
ps -o lstart= -p 1                       # PID 1 start time. Doesn't change on soft-reboot.
systemctl status systemd-soft-reboot.service
```

If `systemd-soft-reboot.service` shows it ran, the pivot happened.

If `findmnt /` shows the old deploy:

- `prepare-soft-reboot` failed silently. Check `/tmp/sr-test.log` if `cache22-reboot --soft` was invoked manually.
- `softRebootCapable` was actually false. Run `sudo cache22-reboot --check` to see what strategy would be picked.

**Fix:** Run a normal hard reboot:

```
sudo cache22-reboot --hard
```

The full reboot path is well-tested and will land on the staged deploy.

## Disk and filesystem

### `/etc` is read-only after a soft-reboot

**Symptom:** Tried to edit a file under `/etc` after a soft-reboot. Got "Read-only file system".

**Cause:** Old behavior. systemd's soft-reboot pivot drops bind mounts not on its preserve list. Cache22's `/etc` bind from `prepare-soft-reboot` was lost during the pivot.

**Fix:** Update to the latest cache22 image. The `50-cache22-etc-rw.conf` drop-in on `ostree-remount.service` ensures `/etc` is rebound as writable early in the post-soft-reboot boot.

For an immediate workaround on an older image:

```
sudo mount --bind /etc /etc
sudo mount -o remount,bind,rw /etc
```

Or hard-reboot, which restores `/etc` via initrd's `ostree-prepare-root`.

### Pacman fails with "Read-only file system"

**Symptom:** `sudo pacman -S <package>` returns "could not write to lock file: Read-only file system".

**Cause:** `/usr` is read-only on cache22. `pacman -S` writes to `/var/lib/pacman/db.lck` and to `/usr/...`.

**Fix:** Use one of:

- [Flatpak](../customization/flatpak/) for GUI apps.
- [Distrobox](../customization/distrobox/) for CLI tools and dev environments.
- `sudo bootc usroverlay` for temporary `/usr` writes (discarded on reboot). See [usroverlay](../customization/usroverlay/).
- [Fork the repo](../building-and-forking/forking/) and add the package to `packages/*.txt` for permanent inclusion.

### df shows root nearly full but I haven't installed anything

**Symptom:** `df -h /` reports high usage. Investigation shows lots of space under `/sysroot/ostree/repo/objects/`.

**Cause:** ostree keeps the booted, staged, and rollback deploys plus their content. After many upgrades, old objects accumulate even though they're not referenced.

**Fix:** Trigger ostree's normal cleanup:

```
sudo ostree admin cleanup
```

This removes objects no longer referenced by any deploy. Typically frees several GB.

For more aggressive cleanup, prune old log files in `/var/log/journal/`:

```
sudo journalctl --vacuum-time=7d
```

## TPM and LUKS

### `cache22-encryption enroll` fails with "No TPM2 device detected"

**Symptom:** Enroll command exits with the named error.

**Cause:** No TPM2 device is exposed to userspace. Either the firmware doesn't have a TPM2, or it's disabled in firmware.

**Investigation:**

```
ls /dev/tpm*
```

If empty, no TPM2 is available. Check firmware setup for "TPM", "fTPM", "PTT" (Intel), or "PSP" (AMD) settings. Enable.

If `/dev/tpm0` exists but is owned by something other than root, fix permissions:

```
ls -la /dev/tpm*
```

Should be `crw-rw---- root tss`. systemd-cryptenroll runs as root and should access this fine.

### TPM unlock works on hard reboot but not after kexec

See "After kexec, screen is blank" above. The fix is to enroll a PCR 7 fallback keyslot.

### TPM unlock fails after firmware update

**Symptom:** Booted normally yesterday. After installing a firmware update from the vendor (often via fwupd), the system now prompts for the LUKS passphrase instead of auto-unlocking.

**Cause:** Firmware updates change PCR 0-3 (firmware code measurements) or PCR 7 (Secure Boot state). PCR 7 is what cache22's optional fallback keyslot binds to. The keyslot becomes invalid until re-enrolled.

**Fix:** Type the passphrase to boot. Then re-enroll:

```
sudo cache22-encryption remove /dev/<luks-dev>
sudo cache22-encryption enroll /dev/<luks-dev>
```

The PCR 11 signed-policy keyslot is unaffected by firmware updates (the policy is on UKI content, not firmware). If only PCR 11 is enrolled, firmware updates do not break unlock.

## Distrobox

### `distrobox-host-exec` returns nothing silently

**Symptom:** Inside a distrobox, `distrobox-host-exec ls` (or any command) returns no output, no error, and the exit code is 0.

**Cause:** `distrobox-host-exec` uses `host-spawn` which connects to the `org.freedesktop.Flatpak` DBus service on the host. If flatpak isn't installed on the host, the service isn't there, and host-spawn silently fails.

**Fix:** Verify flatpak is installed on the host:

```
# On the host, NOT inside distrobox:
which flatpak
systemctl list-units flatpak-system-helper.service
```

If flatpak is missing, `distrobox-host-exec` cannot work. cache22 ships flatpak in all variants by default, so this should be present unless explicitly removed.

If flatpak is installed but `distrobox-host-exec` still fails, check that DBus is correctly set up:

```
echo $DBUS_SESSION_BUS_ADDRESS
```

If empty, your shell is running without a DBus session. `dbus-launch distrobox enter <name>` works around this.

## Build / fork

### GitHub Actions image build fails with "no space left on device"

**Symptom:** Fork's CI fails during `buildah bud` with disk-full errors.

**Cause:** GitHub-hosted runners have ~14 GB free. KDE variants can hit this with Steam, full Plasma, etc.

**Fix:** Add a step at the start of the workflow to free space:

```yaml
- name: Free disk space
  run: |
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/share/boost
    sudo apt-get clean
    df -h
```

GitHub maintains [a recommended approach](https://github.com/actions/runner-images/issues/2840) for freeing space. Self-hosted runners avoid this entirely.

### Build succeeds but image won't boot in cache22-install

**Symptom:** Fork's `:rolling` image builds successfully but the live ISO's `cache22-install --image` fails with errors during the deploy step.

**Cause:** Common causes:

- The image is missing required cache22 files (e.g., overlay was incomplete).
- The image lacks the per-machine signing chain expectations.
- `bootc container lint` would have caught this but was skipped.

**Investigation:** Pull the image locally and inspect:

```
podman pull ghcr.io/<your-username>/cache22-<variant>:rolling
podman run --rm -it ghcr.io/<your-username>/cache22-<variant>:rolling bootc container lint
```

The lint output indicates what's missing or wrong.

**Fix:** Compare with a working cache22 build. The most common cause is an overlay that wasn't applied correctly because `system_files/<variant>/` is missing files that `system_files/common/` expects.

## Other

### `cache22-update` shows the desktop notification multiple times

**Symptom:** Each `cache22-update` (or each bootc state change) pops a "cache22 update ready" notification. Annoying when the timer fires daily.

**Cause:** Older cache22 images notified on every state-changing event. Newer images only notify on transitions: when the marker file is being created or its content changes.

**Fix:** Update to the latest cache22 image. `cache22-pending-motd.service` only notifies on actual transitions.

### Want to disable the desktop notification entirely

Edit `/usr/libexec/cache22/refresh-pending-motd` and remove or comment out the `notify-send` block. Note that this needs to happen via image fork (or a `bootc usroverlay` that gets re-applied each boot). Direct edits to `/usr/libexec` are read-only on cache22.

For a fork-based approach, copy the modified script to `system_files/common/usr/libexec/cache22/refresh-pending-motd` in your fork.

## Where to ask for help

- File issues at [github.com/cmspam/cache22/issues](https://github.com/cmspam/cache22/issues).
- Include the output of `sudo cache22-secureboot status`, `sudo bootc status`, and relevant journal extracts.
- For boot issues, attach the output of `sudo journalctl -b -1` from a successful boot if available.
