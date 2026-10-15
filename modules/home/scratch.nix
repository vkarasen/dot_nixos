# Dendritic aspect: scratch (home-manager class). Exports the canonical
# scratch area (my.scratchArea) as the SCRATCH_AREA env var for shells and
# agent tooling. A leading ~/ is expanded against the real home directory so
# the value is a concrete absolute path at runtime.
{...}: {
  flake.modules.homeManager.scratch = {
    config,
    lib,
    ...
  }: let
    scratchDir =
      if lib.hasPrefix "~/" config.my.scratchArea
      then config.home.homeDirectory + lib.removePrefix "~" config.my.scratchArea
      else config.my.scratchArea;
  in {
    home.sessionVariables.SCRATCH_AREA = scratchDir;
  };
}
