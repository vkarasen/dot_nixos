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
        # pi as a single-file Bun executable (derivation in flake/_pi-bun.nix).
        # An overlay rather than only a perSystem package because the
        # home-manager configs consume this same pkgs instance via
        # `withSystem`, and `programs.pi-coding-agent.package = pkgs.pi-bun`
        # has to resolve there.
        (final: prev: {
          pi-bun = final.callPackage ./_pi-bun.nix {};
        })
      ];
    };

    formatter = inputs.nixpkgs.legacyPackages.${system}.alejandra;
  };
}
