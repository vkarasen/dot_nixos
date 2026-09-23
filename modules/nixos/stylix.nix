# Dendritic aspect: stylix (NixOS class) — holistic base16 theming for the
# desktop surface (GTK, console, greeter, ...). The terminal/CLI layer stays
# with catppuccin-nix (see modules/home/external.nix and the desktop aspect),
# so Stylix targets the DE surface only.
{...}: {
  flake.modules.nixos.stylix = {pkgs, config, ...}: {
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
      # The gtk target is home-manager-only: Stylix's system->home forwarding
      # does not copy stylix.targets.gtk, so it must be enabled HERE (the
      # system-level targets.gtk.enable above only supplies programs.dconf.enable).
      gtk = {
        enable = true;
        # Stylix emits @define-color, which libadwaita >= 1.9 no longer reads
        # (stylix #2472). Restate the key libadwaita colours as element-scoped
        # CSS variables (still honoured), generated from the same palette so it
        # stays in sync with the scheme. Accent = base0E (catppuccin mauve);
        # swap to base0D (blue) / base0C (teal) to change it.
        extraCss = let c = config.lib.stylix.colors; in ''
          window {
            --accent-color: #${c.base0E-hex};
            --accent-bg-color: #${c.base0E-hex};
            --accent-fg-color: #${c.base00-hex};
            --window-bg-color: #${c.base00-hex};
            --window-fg-color: #${c.base05-hex};
            --view-bg-color: #${c.base00-hex};
            --view-fg-color: #${c.base05-hex};
            --headerbar-bg-color: #${c.base01-hex};
            --headerbar-fg-color: #${c.base05-hex};
            --sidebar-bg-color: #${c.base01-hex};
            --card-bg-color: #${c.base01-hex};
            --popover-bg-color: #${c.base01-hex};
            --dialog-bg-color: #${c.base01-hex};
            --destructive-color: #${c.base08-hex};
            --success-color: #${c.base0B-hex};
            --warning-color: #${c.base0A-hex};
          }
        '';
      };
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
