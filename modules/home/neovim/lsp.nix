{pkgs, ...}: let
  nodepkgs = with pkgs.nodePackages; [
    bash-language-server
  ];
in {
  home.packages = with pkgs;
    [
      nil
      alejandra
      shfmt
    ]
    ++ nodepkgs;

  programs = {
    nixvim = {
      plugins = {
        lsp = {
          enable = true;
          inlayHints = true;
          keymaps = {
            lspBuf = {
              "<leader>cf" = "format";
              "<leader>ca" = "code_action";
            };
          };
          servers = {
            bashls = {
              enable = true;
              settings.formatting.command = ["shfmt"];
            };
            nil_ls = {
              enable = true;
              settings = {
                formatting.command = ["alejandra" "-qq"];
                nixpkgs.expr = "import <nixpkgs> {}";
              };
            };
            pyright = {
              enable = true;
            };
          };
        };
        cmp = {
          enable = true;
          autoEnableSources = true;

          settings.sources = [
            {name = "nvim_lsp";}
            {name = "luasnip";}
            {name = "path";}
            {name = "buffer";}
          ];
          settings = {
            snippet.expand =
              #lua
              ''
                function(args)
                    require('luasnip').lsp_expand(args.body)
                end

              '';
          };
        };
        luasnip.enable = true;
        friendly-snippets.enable = true;
        rustaceanvim = {
          enable = true;
          settings = {
            rust-analyzer = {
              check = {
                command = "clippy";
              };
              inlayHints = {
                lifetimeElisionHints = {
                  enable = "always";
                };
              };
              cargo = {
                allFeatures = true;
              };
            };
          };
        };
      };
      extraConfigLua =
        #lua
        ''
          local ls = require("luasnip")

          vim.keymap.set({"i"}, "<C-l>", function() ls.expand() end, {silent = true})

          vim.keymap.set({"i", "s"}, "<C-k>", function() ls.jump( 1) end, {silent = true})

          vim.keymap.set({"i", "s"}, "<C-j>", function() ls.jump(-1) end, {silent = true})

          vim.keymap.set({"i", "s"}, "<C-E>", function()
            if ls.choice_active() then
                ls.change_choice(1)
            end
          end, {silent = true})
        '';
    };
  };
}
