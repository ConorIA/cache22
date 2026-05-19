# cache22 VPS kexec installer

A NixOS-based live environment used to install cache22 onto VPSes that
cannot mount custom ISOs. Built as a kexec tarball: the user untars it
into `/root/` on their existing VPS (Debian, Ubuntu, CentOS, Alpine,
Arch), runs `/root/kexec/run`, and after a brief in-place reboot lands
in a fresh NixOS environment with `cache22-install` on PATH.

The boot environment is upstream NixOS's `kexec-installer` module from
`nix-community/nixos-images`. It captures the host's network config and
SSH keys before kexec and reapplies them on the new side via
`systemd-networkd` with MAC-based matching, so SSH access survives the
in-place reboot on essentially every cloud hypervisor.

## Building locally

Requires Nix with flakes enabled.

    cd installer/nixos-kexec
    nix build .#kexec-tarball
    ls -lh result/

The tarball is at `result/nixos-kexec-installer-x86_64-linux.tar.gz`.

## Pinning

`nixpkgs` is pinned to the `nixos-25.11` channel via the flake input.
The kernel is `boot.kernelPackages = pkgs.linuxPackages_latest`, which
resolves to the newest stable kernel packaged in that channel at the
time `flake.lock` was last updated.

To refresh the inputs:

    nix flake update
