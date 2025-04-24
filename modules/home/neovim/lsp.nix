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
      extraPlugins = [
        (pkgs.vimUtils.buildVimPlugin {
          name = "colorful-menu";
          src =
            pkgs.nix-gitignore.gitignoreSourcePure [
              "repro.lua"
            ] (pkgs.fetchFromGitHub {
              owner = "xzbdmw";
              repo = "colorful-menu.nvim";
              rev = "6a818a5e9fe0b0b09655bd4822ec0cb5c0a8dd91";
              hash = "sha256-x9H7mNCB5UBWd7Sog9SDdHyM8XlR15vVGgtGM5/qucw=";
            });
        })
      ];
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
            clangd = {
              enable = true;
            };
            mesonlsp = {
              enable = true;
            };
          };
        };
        cmp = {
          enable = true;
          autoEnableSources = true;

          settings = {
            sources = [
              {name = "nvim_lsp";}
              {name = "luasnip";}
              {name = "path";}
              {name = "buffer";}
              {
                name = "buffer";
                # Words from other open buffers can also be suggested.
                option.get_bufnrs.__raw = "vim.api.nvim_list_bufs";
              }
            ];
            snippet.expand =
              #lua
              ''
                function(args)
                    require('luasnip').lsp_expand(args.body)
                end

              '';
            mapping = {
              "<C-u>" = "cmp.mapping.scroll_docs(-4)";
              "<C-d>" = "cmp.mapping.scroll_docs(4)";
              "<C-Space>" = "cmp.mapping.complete()";
              "<C-e>" = "cmp.mapping.close()";
              "<C-n>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
              "<C-p>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
              "<Tab>" = "cmp.mapping.confirm({ select = true })";
            };
            formatting.fields = [
              "kind"
              "abbr"
            ];
          };
        };
        lspkind = {
          enable = true;
          mode = "symbol";
          cmp = {
            maxWidth = 30;
            after =
              #lua
              ''
                function(entry, vim_item, kind)
                    local highlights_info = require("colorful-menu").cmp_highlights(entry)

                    -- if highlight_info==nil, which means missing ts parser, let's fallback to use default `vim_item.abbr`.
                    -- What this plugin offers is two fields: `vim_item.abbr_hl_group` and `vim_item.abbr`.
                    if highlights_info ~= nil then
                      vim_item.abbr_hl_group = highlights_info.highlights
                      vim_item.abbr = highlights_info.text
                    end

                    return vim_item
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
