{ config, lib, pkgs, modulesPath, ... }:

let
  installRuntimeDeps = with pkgs; [
    bootc skopeo
    btrfs-progs cryptsetup
    parted gptfdisk dosfstools
    e2fsprogs xfsprogs
    sbctl efibootmgr efivar mokutil
    openssl jq python3
    util-linux iproute2 nettools
    curl gnutar xz gzip
    systemd coreutils gnused gawk gnugrep
  ];

  repairRuntimeDeps = with pkgs; [
    bootc skopeo btrfs-progs cryptsetup
    sbctl efibootmgr mokutil
    jq util-linux systemd coreutils
  ];

  # Wrap the existing scripts with PATH set to the deps above. We use
  # runCommand + wrapProgram rather than writeShellApplication because
  # the latter gates the build on shellcheck-clean, which the existing
  # scripts aren't (and don't need to be — they ship in the Fedora ISO
  # without that constraint).
  cache22-install = pkgs.runCommand "cache22-install" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    install -Dm0755 ${./cache22-install} $out/bin/cache22-install
    wrapProgram $out/bin/cache22-install \
        --prefix PATH : ${lib.makeBinPath installRuntimeDeps}
  '';

  cache22-repair = pkgs.runCommand "cache22-repair" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    install -Dm0755 ${./cache22-repair} $out/bin/cache22-repair
    wrapProgram $out/bin/cache22-repair \
        --prefix PATH : ${lib.makeBinPath repairRuntimeDeps}
  '';

in {
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" "xfs" ];

  environment.systemPackages = with pkgs; [
    cache22-install
    cache22-repair
    htop tmux vim git tcpdump strace lsof pciutils usbutils
  ];

  users.motd = ''

    cache22 VPS installer (NixOS-based kexec environment)

    Run:  cache22-install     to install cache22 to disk
          cache22-repair      to reinstall the OS image without touching /var

    The variant picker, partitioning, LUKS, user creation, and bootloader
    setup are identical to the USB installer.

    Docs: https://github.com/cmspam/cache22
  '';

  system.stateVersion = "25.11";
}
