# Assemble nixosConfigurations from the dendritic aspect store, mirroring
# home-configurations.nix. A host file (modules/hosts/<name>.nix) declares
# itself via flake.nixosHosts.<name> and lists the shared system aspects it
# opts into; this module folds them into a NixOS system with the home-manager
# aspects nested under users.vkarasen.
{
  inputs,
  config,
  withSystem,
  lib,
  ...
}: {
  options.flake.nixosHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.modules = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [];
          description = "Shared system aspects this host opts into.";
        };
      }
    );
    default = {};
    description = "NixOS hosts: hostname -> { modules = [shared aspects]; }.";
  };

  config.flake.nixosConfigurations = withSystem "x86_64-linux" (
    {pkgs, ...}:
      lib.mapAttrs (
        name: host:
          inputs.nixpkgs.lib.nixosSystem {
            inherit pkgs;

            specialArgs = {inherit inputs;};

            modules =
              host.modules
              # the host's own aspect (hardware, hostname, per-host overrides)
              ++ [config.flake.modules.nixos.${name}]
              # class-agnostic options (my.*) in the NixOS module system
              ++ (builtins.attrValues (config.flake.modules.generic or {}))
              ++ [
                inputs.home-manager.nixosModules.home-manager
                {
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    users.vkarasen = {
                      imports =
                        (builtins.attrValues config.flake.modules.homeManager)
                        ++ (builtins.attrValues (config.flake.modules.generic or {}));
                      # the personal machine is always the private variant
                      my.is_private = lib.mkForce true;
                    };
                  };
                }
              ];
          }
      )
      config.flake.nixosHosts
  );
}
