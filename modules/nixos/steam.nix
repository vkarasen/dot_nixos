# Dendritic aspect: steam (NixOS class) — the Steam client plus the system-side
# bits it needs: 32-bit graphics drivers (for 32-bit games and Wine/Proton) and
# udev rules for Steam Input controllers. The user-space overlay (MangoHud)
# lives in the home-class counterpart modules/home/steam.nix.
#
# Impermanence note: Steam's FHS runtime lives in the Nix store; the game
# library, saves, shader caches, and Proton prefixes are runtime state under
# ~/.local/share/Steam — which is persistent because /home is its own btrfs
# subvolume, not the ephemeral root that boot.nix rolls back. Nothing Steam
# needs lives in the erased root, so no persistence entry is required here.
{...}: {
  flake.modules.nixos.steam = {...}: {
    programs.steam.enable = true;

    # 32-bit Mesa/Vulkan drivers. Some nixpkgs imply this when Steam is
    # enabled; set it explicitly to self-document the requirement.
    hardware.graphics.enable32Bit = true;

    # udev rules for the Steam Controller / Steam Input devices.
    hardware.steam-hardware.enable = true;

    # /games is a dedicated btrfs subvolume (modules/nixos/disks.nix) for the
    # Steam library. The subvolume root starts root-owned; chown it at boot so
    # Steam (running as the user) can add a library folder there. `z` adjusts
    # the existing mountpoint rather than creating it; tmpfiles-setup runs
    # after local-fs.target, so the mount is already up.
    systemd.tmpfiles.rules = [
      "z /games 0755 vkarasen users -"
    ];
  };
}
