{pkgs, ...}: {
  programs.neovim = {
    plugins = with pkgs.vimPlugins; [
      (
        nvim-treesitter.withPlugins (
          p: with p; nvim-treesitter.allGrammars ++ [tree-sitter-lua]
        )
      )
      nvim-treesitter-context
      nvim-treesitter-textobjects
    ];
    extraLuaConfig =
      /*
      lua
      */
      ''
        require'nvim-treesitter.configs'.setup{
        	highlight = {
        	    enable = true,
        	},
        	indent = {
        	    enable = false,
        	    disable = {},
        	},

        }
        require("treesitter-context").setup()
      '';
  };
}
