# Standalone home-manager modules for cross-flake consumption.
# These are the reusable "library" pieces a corporate or other flake can import
# without taking the whole dendritic aspect store.
{...}: {
  # The pi option machinery: programs.pi-coding-agent.skills.
  # Import this in any flake that wants the structured skills option
  # wired automatically into settings.skills.
  # programs.pi-coding-agent.{enable,settings,extraPackages} are declared by
  # home-manager's built-in pi-coding-agent module — no extra import needed.
  flake.homeModules.pi-module = ../home/pi/_module.nix;

  # The Tridactyl option machinery: programs.tridactyl.
  # Import this in any flake that wants the programs.tridactyl option set
  # (settings/binds/extraConfig) wired to the tridactylrc + Firefox extension.
  flake.homeModules.tridactyl-module = ../home/tridactyl/_module.nix;

  # The generated Tridactyl index machinery: programs.tridactyl-index.
  # Import this (with source = <tridactyl source tree>) in any flake that wants
  # the generated settings/ex-command index materialized at
  # xdg.configFile."tridactyl/index.json" and wired to the television
  # `tridactyl` channel. Independent of programs.tridactyl.
  flake.homeModules.tridactyl-index-module = ../home/tridactyl/_index-module.nix;

  # The generated Firefox-preference index machinery: programs.ffpref.
  # Import this in any flake that wants the generated pref index materialized
  # at xdg.configFile."ffprefs/index.json" and wired to the television `ffpref`
  # channel.
  flake.homeModules.ffpref-module = ../home/firefox/_index-module.nix;

  # The herdr option machinery: programs.herdr.{enable, settings}.
  # Import this in any flake that wants herdr config wired to
  # xdg.configFile."herdr/config.toml" automatically.
  flake.homeModules.herdr-module = ../home/herdr/_module.nix;
}
