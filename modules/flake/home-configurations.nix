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
          # The standalone home config is the TUI-only variant: no display
          # surface, so the GUI aspects (desktop, kanshi) gate themselves off
          # via config.my.gui.enable.
          {my.gui.enable = false;}

          # Stylix home module. modules/home/desktop.nix sets stylix.targets.*
          # behind a mkIf, and the NixOS module system requires an option to
          # be *declared* wherever it is *defined* — mkIf only defers the
          # value, it does not remove the definition. So the module must be
          # imported here too, not just on the NixOS side (where it arrives via
          # stylix.nixosModules.stylix + homeManagerIntegration.autoImport).
          # With gui.enable=false and stylix.enable=false (its default) this is
          # inert: a declaration stub, not an active dependency.
          inputs.stylix.homeModules.stylix

          # vkarasen's personal machine is always the private variant.
          {my.is_private = lib.mkForce true;}
        ];
    });
}
