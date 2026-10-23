# flake-parts' `systems` option has NO default: without this, every
# `perSystem` block evaluates to nothing (empty checks/packages/apps) and
# `nix flake check` passes vacuously.
{...}: {
  systems = ["x86_64-linux" "aarch64-linux"];
}
