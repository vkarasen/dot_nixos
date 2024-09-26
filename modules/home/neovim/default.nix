{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./git.nix
    ./lsp.nix
    ./treesitter.nix
    ./telescope.nix
    ./prelude.nix
  ];
  home.packages = with pkgs; [
  ];

  programs = {
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins = with pkgs.vimPlugins; [
        lualine-nvim
      ];

      extraLuaConfig =
        /*
        lua
        */
        ''
          require('lualine').setup()

        '';
    };
  };
}
