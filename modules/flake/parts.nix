# Flake-parts skeleton: opt into flake.modules.<class> storage, declare
# systems, and configure a single allowUnfree pkgs (with the `stable`, `pi-bun`
# and `tack` overlays)
# shared by every perSystem output and home configuration.
# The overlays are also exposed as flake.overlays.* so downstream flakes
# (the corporate flake) can apply them to their own nixpkgs.
{inputs, ...}: let
  lib = inputs.nixpkgs.lib;
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
  # The tack 2.0.0 binary from the tack flake, so the on-PATH `tack` matches
  # the `.tack/` files (nixpkgs ships 0.1.1, which cannot read them: group
  # updates, `$declared`, `resolver out of date`).
  tack-overlay = final: prev: {
    tack = inputs.tack.packages.${final.system}.tack;
  };
  # The hyprland flake builds these packages with their deps in `buildInputs`,
  # but nixpkgs' recipes for the same packages put them in
  # `propagatedBuildInputs`, and downstream nixpkgs packaging relies on that
  # propagation for pkg-config resolution. Examples that broke once
  # hyprland-packages substituted the flake builds:
  #   - hyprlock 0.9.7: `pkg_check_modules(hyprutils>=0.11.0 hyprgraphics>=0.1.6)`
  #     with no hyprutils in its buildInputs -> hyprutils not found.
  #   - hyprpolkitagent 0.2.0: hyprtoolkit.pc Require aquamarine, which the
  #     flake hyprtoolkit does not propagate -> "Package 'aquamarine',
  #     required by 'hyprtoolkit', not found".
  # Mirror the propagation nixpkgs declares so those recipes keep configuring.
  # (Duplicates with what the flake builds already propagate are harmless.)
  hypr-deps-propagation-overlay = lib.composeManyExtensions (
    lib.mapAttrsToList (name: deps: final: prev: {
      ${name} = prev.${name}.overrideAttrs (old: {
        propagatedBuildInputs =
          (old.propagatedBuildInputs or [])
          ++ map (dep: final.${dep}) deps;
      });
    }) {
      aquamarine = ["hyprutils" "libdrm" "wayland"];
      hyprgraphics = ["cairo" "hyprutils" "libGL" "pango"];
      hyprtoolkit = ["aquamarine" "hyprgraphics" "hyprutils"];
      hyprutils = ["pixman"];
    }
  );
  default-overlay = lib.composeManyExtensions [
    stable-overlay
    pi-bun-overlay
    tack-overlay
    inputs.hyprland.overlays.hyprland-packages
    hypr-deps-propagation-overlay
  ];
in {
  imports = [inputs.flake-parts.flakeModules.modules];

  # ponytail: x86_64-linux only for now; add aarch64-darwin here when nix-darwin lands.
  systems = ["x86_64-linux"];

  flake.overlays = {
    stable = stable-overlay;
    pi-bun = pi-bun-overlay;
    tack = tack-overlay;
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
