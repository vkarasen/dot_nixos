# Standalone nvim package built from the shared nixvim module tree
# (modules/_nixvim, ignored by import-tree because of the leading underscore).
# The same tree is imported by the neovim home aspect, so config stays single-source.
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    packages.nvim = inputs.nixvim.legacyPackages.${system}.makeNixvimWithModule {
      inherit pkgs;
      module = import ../_nixvim;
    };
  };
}
