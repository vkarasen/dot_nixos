# Dendritic aspect: tack (home-manager class) - flake-input pinning CLI.
{...}: {
  flake.modules.homeManager.tack = {pkgs, ...}: {
    home.packages = [pkgs.tack];
  };
}
