{ config, ... }:
{
  programs = {
    nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins.nixd.settings.options.home_manager.expr = ''(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName or "vkarasen"}.options'';

      imports = [
        ../../base/nixvim-base.nix
        ./nixvim/git.nix
        ./nixvim/lsp.nix
        ./nixvim/treesitter.nix
        ./nixvim/telescope.nix
        ./nixvim/markdown.nix
        ./nixvim/lint.nix
        ./nixvim/latex.nix
        ./nixvim/mini.nix
        ./nixvim/which-key.nix
        ./nixvim/dap.nix
      ];
    };
  };
}

