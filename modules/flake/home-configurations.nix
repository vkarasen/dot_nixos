# Assemble homeConfigurations from the dendritic aspect store. The standalone
# portable config opts into the universal `core` bundle (plus the class-
# agnostic generic.* aspects) — the TUI-only variant, no desktop/laptop.
# Adding a new always-on home aspect: add it to modules/home/core.nix.
{
  inputs,
  config,
  withSystem,
  lib,
  ...
}: {
  flake.homeConfigurations.vkarasen = withSystem "x86_64-linux" ({pkgs, ...}:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      extraSpecialArgs = {
        # inputs is the only extraSpecialArg still threaded explicitly.
        # std, ast-bro, nixvimOptions were removed: every aspect that needed
        # them now closes over inputs.* at flake-parts evaluation time instead.
        inherit inputs;
      };

      modules =
        [
          # The standalone portable config is the TUI-only variant: it opts
          # into the universal `core` bundle and omits the machine-specific
          # desktop/laptop aspects, so my.gui.enable and my.laptop.enable
          # stay false (their defaults). No Stylix either — the per-user
          # stylix.targets live on the NixOS side (modules/nixos/stylix.nix),
          # so no home aspect references `stylix` and no Stylix home module
          # needs importing here.
          config.flake.modules.homeManager.core
        ]
        ++ builtins.attrValues (config.flake.modules.generic or {})
        ++ [
          # vkarasen's personal machine is always the private variant.
          {my.is_private = lib.mkForce true;}
        ];
    });
}
