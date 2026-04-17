# Declare dendritic flake options so multiple modules can contribute to them
# Replaces home-modules.nix — provides flake.constants and flake.modules namespaces
#
# flake-parts declares options.flake as submoduleWith, so we must extend
# its internal module list rather than declaring sub-options from outside.
{ lib, ... }: {
  options.flake = lib.mkOption {
    type = lib.types.submoduleWith {
      modules = [{
        options = {
          constants = lib.mkOption {
            type = lib.types.lazyAttrsOf lib.types.raw;
            default = {};
            description = "Constants exported by this flake";
          };

          modules = lib.mkOption {
            type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
            default = {};
            description = "Modules exported by this flake, organized by namespace (e.g. nixvim, homeManager)";
          };
        };
      }];
    };
  };
}

