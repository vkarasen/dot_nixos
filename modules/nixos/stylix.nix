# Dendritic aspect: stylix (NixOS class) — holistic base16 theming for the
# desktop surface (GTK, console, greeter, ...). The terminal/CLI layer stays
# with catppuccin-nix (see modules/home/external.nix and the desktop aspect),
# so Stylix targets the DE surface only.
{...}: {
  flake.modules.nixos.stylix = {pkgs, ...}: {
    stylix = {
      enable = true;
      # Opt-in per-target: Stylix themes only what we enable here; everything
      # else (terminals, CLI tools) stays catppuccin's.
      autoEnable = false;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.noto;
          name = "NotoMono Nerd Font Mono";
        };
      };

      # System-level (DE surface) targets.
      targets = {
        gtk.enable = true;
        console.enable = true; # TTY palette (replaces the manual console.colors)
        regreet.enable = true; # login screen
      };
    };

    # Per-user DE targets (hyprland, waybar, mako, hyprlock, fuzzel). Kept
    # here — not in modules/home/desktop.nix — so the shared home aspect never
    # references `stylix`, which lets the standalone TUI-only home config drop
    # the Stylix home module entirely. The home-manager `stylix` option is
    # declared by the Stylix home module that homeManagerIntegration.autoImport
    # injects into users.vkarasen.
    home-manager.users.vkarasen.stylix.targets = {
      hyprland.enable = true;
      waybar.enable = true;
      mako.enable = true;
      hyprlock.enable = true;
      fuzzel.enable = true;
      # Firefox via firefox-gnome-theme (writes userChrome.css). Deliberately
      # NOT `colorTheme`: that uses the Firefox Color extension, whose settings
      # home-manager seeds via a legacy storage.js that modern Firefox
      # (IndexedDB-backed storage.local) ignores.
      firefox = {
        enable = true;
        profileNames = ["vkarasen"];
        firefoxGnomeTheme.enable = true;
      };
    };
  };
}
