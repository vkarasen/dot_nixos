{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    self',
    ...
  }: let
    rust = import ./_lib.nix {inherit inputs pkgs lib system;};
  in {
    devShells.default = rust.craneLib.devShell {
      checks = self'.checks;
      packages = [rust.toolchain pkgs.cargo-nextest pkgs.cargo-deny pkgs.cargo-audit];
    };

    formatter = pkgs.alejandra;
  };
}
