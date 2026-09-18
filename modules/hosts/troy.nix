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
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.stylix
    config.flake.modules.nixos.lock
  ];

  # Home-manager aspects this host opts into. `core` is the universal tooling;
  # desktop/kanshi are the GUI (a laptop or a desktop PC alike); laptop is the
  # suspend/idle/battery behaviour specific to a laptop. browser follows
  # desktop: it is gated on my.gui.enable, so it only activates on GUI hosts.
  flake.nixosHosts.troy.homeModules = [
    config.flake.modules.homeManager.core
    config.flake.modules.homeManager.desktop
    config.flake.modules.homeManager.browser
    config.flake.modules.homeManager.kanshi
    config.flake.modules.homeManager.laptop
  ];

  flake.modules.nixos.troy = {pkgs, ...}: {
    networking.hostName = "troy";

    system.stateVersion = "26.05";

    # Troy's iGPU is Intel UHD Graphics (Comet Lake, PCI 8086:9b41); the
    # Intel VA-API driver (iHD) enables Firefox hardware video decode, and
    # libva auto-detects iHD. Host-specific hardware belongs here rather than
    # in the shared nixos.desktop aspect, since other hosts using desktop
    # will not be Intel-graphics based.
    hardware.graphics.extraPackages = [pkgs.intel-media-driver];

    # Hardware scan (kernel modules, cpu governor, firmware) is captured after
    # first boot with `nixos-generate-config --no-filesystems` and folded in
    # here — see docs/nixos-install.md §5. Don't import a full hardware-config:
    # disko already declares filesystems/LUKS/swap, and a full scan would clash.
  };
}
