# Dendritic aspect: opencode (home-manager class).
{...}: {
  flake.modules.homeManager.opencode = {
    lib,
    pkgs,
    config,
    ...
  }: {
    config = {
      programs = {
        opencode = {
          enable = true;
        };
      };
    };
  };
}
