# Dendritic aspect: stylix (home-manager class) — the home-side of Stylix.
#
# Stylix's NixOS module would normally inject its home module into every
# home-manager user via `stylix.homeManagerIntegration.autoImport` (default
# true). That injection only happens inside the NixOS assembly, so a
# standalone homeConfiguration (the per-host `vkarasen@<host>` entries built
# by modules/flake/nixos-configurations.nix, or `nh home switch .`) would have
# no `stylix` home option at all. The NixOS side therefore sets
# `homeManagerIntegration.autoImport = false` (see modules/nixos/stylix.nix)
# and this self-contained aspect imports the Stylix home module explicitly and
# owns the per-user DE targets.
#
# It is bundled: modules/home/desktop.nix imports it, so hosts do NOT list it
# in `homeModules` — importing the desktop aspect is what brings Stylix in.
# Stylix stays on by default via `enable = lib.mkDefault my.gui.enable` (the
# derived GUI flag the desktop aspect sets), so a config that reaches this
# aspect without a GUI — and the portable TUI-only homeConfigurations.vkarasen,
# which never imports desktop at all — gets no Stylix home config, while a GUI
# host that wants none can opt out with `stylix.enable = false`. System-level
# theming (console, regreet, dconf) stays on the NixOS side in
# modules/nixos/stylix.nix.
{inputs, ...}: {
  flake.modules.homeManager.stylix = {
    pkgs,
    config,
    lib,
    ...
  }: {
    imports = [inputs.stylix.homeModules.stylix];

    stylix = {
      enable = lib.mkDefault config.my.gui.enable;
      # Opt-in per-target: Stylix themes only what we enable here; everything
      # else (terminals, CLI tools) stays catppuccin's.
      autoEnable = false;
      polarity = "dark";
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

      fonts.monospace = {
        package = pkgs.nerd-fonts.noto;
        name = "NotoMono Nerd Font Mono";
      };

      targets = {
        # The gtk target is home-manager-only: Stylix's system->home forwarding
        # does not copy stylix.targets.gtk, so it must be enabled HERE (the
        # system-level targets.gtk.enable in modules/nixos/stylix.nix only
        # supplies programs.dconf.enable).
        gtk = {
          enable = true;
          # Stylix emits @define-color, which libadwaita >= 1.9 no longer reads
          # (stylix #2472). Restate the key libadwaita colours as element-scoped
          # CSS variables (still honoured), generated from the same palette so it
          # stays in sync with the scheme. Accent = base0E (catppuccin mauve);
          # swap to base0D (blue) / base0C (teal) to change it.
          extraCss = let
            c = config.lib.stylix.colors;
          in ''
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
  };
}
