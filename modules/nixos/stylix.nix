# Dendritic aspect: stylix (NixOS class) — holistic base16 theming for the
# desktop surface (GTK, console, greeter, ...). The terminal/CLI layer stays
# with catppuccin-nix (see modules/home/external.nix and the desktop aspect),
# so Stylix targets the DE surface only.
#
# It is bundled: modules/nixos/desktop.nix imports it, so hosts do NOT list it
# in their `modules` — a host that opts into nixos.desktop gets the system-side
# theming automatically. The home half of Stylix lives in the separate home
# aspect modules/home/stylix.nix, which modules/home/desktop.nix imports.
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

    # The per-user DE targets (gtk/hyprland/waybar/mako/hyprlock/fuzzel/
    # firefox) live in the home aspect modules/home/stylix.nix — the home half
    # of Stylix, imported by modules/home/desktop.nix, not listed per-host.
    # Stylix's own auto-injection of that home module only happens inside the
    # NixOS assembly, which left the standalone `homeConfigurations.vkarasen@
    # <host>` without a `stylix` home option — so that aspect imports the home
    # module explicitly and we disable the automatic import here.
    stylix.homeManagerIntegration.autoImport = false;
  };
}
