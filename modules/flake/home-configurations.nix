# Assemble homeConfigurations from the dendritic aspect store. Every
# flake.modules.homeManager.* (and the class-agnostic generic.*) aspect is
# folded into the single vkarasen configuration. New aspect file => new
# functionality, no edits here.
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
        builtins.attrValues config.flake.modules.homeManager
        ++ builtins.attrValues (config.flake.modules.generic or {})
        ++ [
          # The standalone home config has no NixOS side, so the Stylix home
          # module (whose options modules/home/desktop.nix sets) is imported
          # here explicitly. In the NixOS config it arrives via
          # stylix.nixosModules.stylix + homeManagerIntegration.autoImport.
          inputs.stylix.homeModules.stylix
          # vkarasen's personal machine is always the private variant.
          {my.is_private = lib.mkForce true;}
        ];
    });
}
