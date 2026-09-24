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
        options.homeModules = lib.mkOption {
          type = lib.types.listOf lib.types.raw;
          default = [];
          description = "Home-manager aspects this host opts into.";
        };
        options.exposeHomeConfiguration = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Also expose a standalone homeConfigurations.<user>@<host> so `nh home switch .` resolves to this host's home config (unknown hosts fall back to homeConfigurations.<user>).";
        };
      }
    );
    default = {};
    description = "NixOS hosts: hostname -> { modules = [shared aspects]; }.";
  };

  # flake-parts ships no built-in `homeConfigurations` output module (it has
  # `nixosConfigurations`, but nothing for home-manager), so the attribute is
  # undeclared/freeform and therefore accepts only a SINGLE definition —
  # modules/flake/home-configurations.nix already owns it. Declaring it here
  # makes it a mergeable attrs keyed by config name, so that file's portable
  # `vkarasen` and this file's per-host `vkarasen@<host>` entries coexist.
  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = {};
    description = "home-manager configurations, keyed by `nh home switch` name: `<user>` (portable fallback) and `<user>@<host>` (per host).";
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
                inputs.stylix.nixosModules.stylix
                inputs.home-manager.nixosModules.home-manager
                {
                  # Machine identity + OS class, exposed to both the NixOS
                  # module system (my.*) and the nested home-manager config.
                  my.is_nixos = true;
                  my.host = name;
                  home-manager = {
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    users.vkarasen = {
                      imports =
                        host.homeModules
                        ++ (builtins.attrValues (config.flake.modules.generic or {}));
                      # the personal machine is always the private variant
                      my.is_private = lib.mkForce true;
                      my.is_nixos = true;
                      my.host = name;
                    };
                  };
                }
              ];
          }
      )
      config.flake.nixosHosts
  );

  # Standalone (non-nested) home configs, one per host, named `<user>@<host>`
  # because that is exactly the lookup order `nh home switch .` uses:
  # homeConfigurations.<user>@<hostname>, then homeConfigurations.<user>.
  # These mirror the nested config in the nixosConfigurations above: same
  # host.homeModules, same generic my.* aspects, same forced identity values.
  # Only home aspects are visible here — nothing set via
  # `home-manager.users.vkarasen` on the NixOS side reaches this config, which
  # is why the home-side Stylix config is an aspect (modules/home/stylix.nix).
  config.flake.homeConfigurations = withSystem "x86_64-linux" (
    {pkgs, ...}:
      lib.mapAttrs' (
        name: host:
          lib.nameValuePair "vkarasen@${name}" (
            inputs.home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = {inherit inputs;};
              modules =
                host.homeModules
                ++ (builtins.attrValues (config.flake.modules.generic or {}))
                ++ [
                  {
                    my.is_private = lib.mkForce true;
                    my.is_nixos = true;
                    my.host = name;
                  }
                ];
            }
          )
      )
      (lib.filterAttrs (_: host: host.exposeHomeConfiguration) config.flake.nixosHosts)
  );
}
