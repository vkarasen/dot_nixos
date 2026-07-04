# Flake-parts skeleton: opt into flake.modules.<class> storage, declare
# systems, and configure a single allowUnfree pkgs (with the `stable` overlay)
# shared by every perSystem output and home configuration.
{inputs, ...}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  # ponytail: x86_64-linux only for now; add aarch64-darwin here when nix-darwin lands.
  systems = ["x86_64-linux"];

  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        (final: prev: {
          stable = import inputs.nixpkgs-stable {inherit system;};
        })
      ];
    };

    formatter = inputs.nixpkgs.legacyPackages.${system}.alejandra;
  };
}
