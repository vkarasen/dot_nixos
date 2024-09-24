{lib, pkgs, ...}: {
	programs.neovim = {
		plugins = with pkgs.vimPlugins; [
			neogit
			gitsigns-nvim
			diffview-nvim
			nvim-web-devicons
		];
		extraLuaConfig = /* lua */ ''
			require("neogit").setup()
			require("gitsigns").setup()
			require("diffview").setup()
			require("nvim-web-devicons").setup()
		'';
	};
}

