{
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    nil
    alejandra
    nodePackages.bash-language-server
    shfmt
  ];

  programs = {
    neovim = {
      plugins = with pkgs.vimPlugins; [
        nvim-lspconfig
      ];

      extraLuaConfig =
        # lua
        ''

          require('lspconfig').nil_ls.setup{
              settings = {
          	    ['nil'] = {
          	formatting = {
          	    command = { "alejandra", "-qq" }
          	}
          	    }
              }
          }
                 require('lspconfig').bashls.setup{
          	settings = {
          		['bashls'] = {
          	    formatting = {
          		command = { "shfmt" }
          	    }
          		}
          	}
                   }
        '';
    };
  };
}
