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
        ../../../_nixvim/base.nix
        ../../../_nixvim/git.nix
        ../../../_nixvim/lsp.nix
        ../../../_nixvim/treesitter.nix
        ../../../_nixvim/telescope.nix
        ../../../_nixvim/markdown.nix
        ../../../_nixvim/lint.nix
        ../../../_nixvim/latex.nix
        ../../../_nixvim/mini.nix
        ../../../_nixvim/which-key.nix
        ../../../_nixvim/dap.nix
      ];
    };
  };
}

