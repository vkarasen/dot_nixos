# Library module: declares programs.herdr.{enable, settings} options
# and wires them into xdg.configFile."herdr/config.toml".
# Uses pkgs.formats.toml (nixpkgs-native) — no extra flake inputs needed.
# Import via homeModules.herdr-module in any consumer flake.
{ pkgs, lib, config, ... }:
let
  cfg = config.programs.herdr;
  fmt = pkgs.formats.toml { };
in
{
  options.programs.herdr = {
    enable = lib.mkEnableOption "herdr terminal workspace manager";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Herdr configuration written to ~/.config/herdr/config.toml.
        Nested sections map to nested attrsets; run `herdr --default-config`
        for the full reference.

        Note: [[keys.command]] (array-of-tables) is a known limitation of
        pkgs.formats.toml — verify serialisation before adding command entries.
      '';
      example = lib.literalExpression ''
        {
          onboarding = false;
          terminal.default_shell = "nu";
          theme.name = "catppuccin";
          ui.sidebar_width = 32;
          ui.agent_panel_scope = "all";
          ui.toast.delivery = "herdr";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."herdr/config.toml" = lib.mkIf (cfg.settings != { }) {
      source = fmt.generate "herdr-config.toml" cfg.settings;
    };
  };
}
