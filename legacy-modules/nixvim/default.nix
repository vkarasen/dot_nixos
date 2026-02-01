{ ... }:
{
  imports = [
    ../../modules/base/nixvim-base.nix
    ../../modules/aspects/editor/nixvim/git.nix
    ../../modules/aspects/editor/nixvim/lsp.nix
    ../../modules/aspects/editor/nixvim/treesitter.nix
    ../../modules/aspects/editor/nixvim/telescope.nix
    ../../modules/aspects/editor/nixvim/markdown.nix
    ../../modules/aspects/editor/nixvim/lint.nix
    ../../modules/aspects/editor/nixvim/latex.nix
    ../../modules/aspects/editor/nixvim/mini.nix
    ../../modules/aspects/editor/nixvim/which-key.nix
    ../../modules/aspects/editor/nixvim/dap.nix
  ];
}

