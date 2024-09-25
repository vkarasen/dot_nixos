{pkgs, ...}: {
	programs.neovim = {
		plugins = with pkgs.vimPlugins; [
			(
				nvim-treesitter.withPlugins (
					p: with p; nvim-treesitter.allGrammars ++ [tree-sitter-lua]
				)
			)
			nvim-treesitter-context
		];
		extraLuaConfig = /* lua */ ''
			require'nvim-treesitter.configs'.setup{
				highlight = {
				    enable = true,
				},
				indent = {
				    enable = true,
				    disable = {},
				},

			}
			require("treesitter-context").setup()
		'';
	};
}
