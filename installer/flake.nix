{
  description = "cache22 VPS kexec installer — boots a NixOS env via kexec with cache22-install on PATH.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-images = {
      url = "github:nix-community/nixos-images";
      inputs.nixos-stable.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-images, ... }:
    let
      system = "x86_64-linux";
      cache22-kexec = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          nixos-images.nixosModules.kexec-installer
          nixos-images.nixosModules.noninteractive
          # Disable two upstream nixos-images modules we don't need:
          #   - installer.nix adds disko/nixos-facter/bcachefs and
          #     imports latest-zfs-kernel.nix (which caps the kernel
          #     at what ZFS supports).
          #   - zfs-minimal.nix is imported by noninteractive.nix; it
          #     adds zfs to defaultPackages, kernelModules, and
          #     extraModulePackages. ZFS doesn't build against 7.x
          #     kernels and we don't use it.
          # Everything cache22-install actually needs lives in
          # ./nixos-kexec.nix.
          { disabledModules = [
              "${nixos-images}/nix/installer.nix"
              "${nixos-images}/nix/zfs-minimal.nix"
            ];
          }
          ./nixos-kexec.nix
        ];
      };
    in {
      nixosConfigurations.cache22-kexec = cache22-kexec;
      packages.${system} = {
        # Use nixos-images' kexecInstallerTarball, not nixpkgs'
        # upstream kexecTarball. The upstream one only ships a bare
        # kexec script (extracts as a single /root/kexec_nixos
        # symlink with no network/SSH preservation). nixos-images'
        # version produces a /root/kexec/ directory containing the
        # initrd, kernel, kexec binary, and the run script that
        # captures host network config + authorized_keys.
        default = cache22-kexec.config.system.build.kexecInstallerTarball;
        kexec-tarball = cache22-kexec.config.system.build.kexecInstallerTarball;
      };
    };
}
