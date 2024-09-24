{lib, pkgs, ...}: {
		home.packages = with pkgs; [
			nil
		];


		programs = {
			neovim = {
				plugins = with pkgs.vimPlugins; [
					nvim-lspconfig
				];

				extraLuaConfig = /* lua */ ''
					require('lspconfig').nil_ls.setup{}
				'';
			};
		};
}

