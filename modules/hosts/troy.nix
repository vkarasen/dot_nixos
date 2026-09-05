# Dendritic aspect: host "troy" (ThinkPad T14s Gen 1, Intel Comet Lake).
# Declares itself as a NixOS host and lists the shared system aspects it uses.
{
  config,
  lib,
  ...
}: {
  flake.nixosHosts.troy.modules = [
    config.flake.modules.nixos.base
    config.flake.modules.nixos.boot
    config.flake.modules.nixos.disks
    config.flake.modules.nixos.impermanence
    config.flake.modules.nixos.sops
    config.flake.modules.nixos.remote-builder
    config.flake.modules.nixos.wifi
    config.flake.modules.nixos.power
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.stylix
    config.flake.modules.nixos.lock
  ];

  flake.modules.nixos.troy = {pkgs, ...}: {
    networking.hostName = "troy";

    system.stateVersion = "26.05";

    # Hardware scan (kernel modules, cpu governor, firmware) is captured after
    # first boot with `nixos-generate-config --no-filesystems` and folded in
    # here — see docs/nixos-install.md §5. Don't import a full hardware-config:
    # disko already declares filesystems/LUKS/swap, and a full scan would clash.
  };
}
