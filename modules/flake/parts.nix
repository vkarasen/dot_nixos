# Flake-parts skeleton: opt into flake.modules.<class> storage, declare
# systems, and configure a single allowUnfree pkgs (with the `stable` and `pi-bun` overlays)
# shared by every perSystem output and home configuration.
# The overlays are also exposed as flake.overlays.* so downstream flakes
# (the corporate flake) can apply them to their own nixpkgs.
{inputs, ...}: let
  stable-overlay = final: prev: {
    stable = import inputs.nixpkgs-stable {inherit (final) system;};
  };
  # pi as a single-file Bun executable (derivation in flake/_pi-bun.nix).
  # An overlay rather than only a perSystem package because the
  # home-manager configs consume this same pkgs instance via
  # `withSystem`, and `programs.pi-coding-agent.package = pkgs.pi-bun`
  # has to resolve there.
  pi-bun-overlay = final: prev: {
    pi-bun = final.callPackage ./_pi-bun.nix {};
  };
  default-overlay =
    inputs.nixpkgs.lib.composeManyExtensions [stable-overlay pi-bun-overlay];
in {
  imports = [inputs.flake-parts.flakeModules.modules];

  # ponytail: x86_64-linux only for now; add aarch64-darwin here when nix-darwin lands.
  systems = ["x86_64-linux"];

  flake.overlays = {
    stable = stable-overlay;
    pi-bun = pi-bun-overlay;
    default = default-overlay;
  };

  perSystem = {system, ...}: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [default-overlay];
    };

    formatter = inputs.nixpkgs.legacyPackages.${system}.alejandra;
  };
}
