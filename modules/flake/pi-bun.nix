# The Bun single-file build of pi as a flake package (`nix build .#pi-bun`).
# The derivation itself lives in the underscore-prefixed helper (ignored by
# import-tree) and reaches home-manager through the overlay in parts.nix, so
# `programs.pi-coding-agent.package = pkgs.pi-bun` resolves in the home
# configs — they share this perSystem pkgs instance via `withSystem`.
{...}: {
  perSystem = {pkgs, ...}: {
    packages.pi-bun = pkgs.pi-bun;
  };
}
