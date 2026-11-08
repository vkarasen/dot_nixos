# Dendritic aspect: solaar (NixOS class) — the Logitech device manager GUI
# (battery levels, DPI, button remapping for Unifying/Bolt/Lightspeed receivers
# and Bluetooth HID++ devices).
#
# Access to the receiver needs unprivileged hidraw permissions. That comes
# from `hardware.logitech.wireless.enable`, which installs
# `pkgs.logitech-udev-rules` (Solaar's own udev rules); nixpkgs'
# `programs.solaar.enable` already sets it via `lib.mkDefault true`, so no
# separate option is required here. The per-user tray service is opt-in via
# `programs.solaar.userService.enable` and is intentionally left off — solaar
# is launched on demand from the desktop.
{...}: {
  flake.modules.nixos.solaar = {...}: {
    programs.solaar.enable = true;
  };
}
