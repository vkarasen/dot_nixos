# Standalone nixvim configuration - imports base + all aspect modules
# Used by the packages.nvim flake output for a self-contained neovim build
{ ... }:
{
  imports = [
    ./base.nix
    ./git.nix
    ./lsp.nix
    ./treesitter.nix
    ./telescope.nix
    ./markdown.nix
    ./lint.nix
    ./latex.nix
    ./mini.nix
    ./which-key.nix
    ./dap.nix
  ];
}

