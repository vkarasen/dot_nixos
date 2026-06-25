# Standalone home-manager modules for cross-flake consumption.
# These are the reusable "library" pieces a corporate or other flake can import
# without taking the whole dendritic aspect store.
{ ... }: {
  # The pi option machinery: programs.pi-coding-agent.{skills, promptTemplates}.
  # Import this in any flake that wants the structured skills/templates options
  # wired automatically into settings.skills / settings.prompts.
  # programs.pi-coding-agent.{enable,settings,extraPackages} are declared by
  # home-manager's built-in pi-coding-agent module — no extra import needed.
  flake.homeModules.pi-module = ../home/pi/_module.nix;

  # The herdr option machinery: programs.herdr.{enable, settings}.
  # Import this in any flake that wants herdr config wired to
  # xdg.configFile."herdr/config.toml" automatically.
  flake.homeModules.herdr-module = ../home/herdr/_module.nix;
}
