# Put lua config here that should be loaded first
{...}: {
	programs.neovim.extraLuaConfig = /* lua */  ''

		vim.g.mapleader = ";"
		vim.g.maplocalleader = " "
		vim.o.number = true
		vim.o.relativenumber = true
	'';
}
