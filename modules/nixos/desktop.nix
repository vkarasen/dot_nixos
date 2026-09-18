# Dendritic aspect: desktop (NixOS class) — Hyprland Wayland compositor.
# The user-facing apps (ghostty, waybar, mako, fuzzel, clipboard/screenshot
# tools) and their config live in the home-manager aspect
# modules/home/desktop.nix.
{...}: {
  flake.modules.nixos.desktop = {pkgs, ...}: {
    # Hyprland, the dynamic tiling Wayland compositor. Enabling it also wires
    # up xdg-desktop-portal-hyprland (portalPackage default) for screen
    # sharing. Launch it from a TTY with `start-hyprland` (the module's
    # wrapper, on the system PATH); the auto-start hook lives in
    # modules/home/desktop.nix via programs.bash.profileExtra.
    programs.hyprland.enable = true;

    # OpenGL/Mesa infrastructure Hyprland needs for EGL rendering on the iGPU.
    # VA-API decode drivers are host-specific hardware: the Intel iHD driver
    # for this host lives in modules/hosts/troy.nix, not here — other hosts
    # using nixos.desktop may not be Intel-graphics based.
    hardware.graphics.enable = true;

    # brightnessctl's udev rules grant the `video` (backlight) and `input`
    # (keyboard LEDs) groups write access, so the Fn brightness keys work
    # without root. The user is in both groups (modules/nixos/base.nix).
    services.udev.packages = [pkgs.brightnessctl];
  };
}
