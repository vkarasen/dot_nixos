{
  pkgs,
  config,
  ...
}: let
  nodepkgs = with pkgs.nodePackages; [
    bash-language-server
  ];
in {
  home.packages = with pkgs;
    [
      nil
      alejandra
      shfmt
      black
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
            diagnostic = {
              "<leader>cj" = "goto_next";
              "<leader>ck" = "goto_prev";
            };
            lspBuf = {
              "<leader>ca" = "code_action";
              "<leader>cK" = "hover";
              "<leader>cD" = "definition";
            };
            extra = [
              {
                action = "<CMD>Lspsaga outline<Enter>";
                key = "<leader>co";
              }
              {
                action = "<CMD>Lspsaga finder<Enter>";
                key = "<leader>cF";
              }
              {
                action = "<CMD>Lspsaga rename<Enter>";
                key = "<leader>cr";
              }
              {
                action = "<CMD>Lspsaga peek_definition<Enter>";
                key = "<leader>cd";
              }
              {
                action = "<CMD>Lspsaga peek_type_definition<Enter>";
                key = "<leader>ct";
              }
              {
                action = "<CMD>Lspsaga goto_type_definition<Enter>";
                key = "<leader>cT";
              }
              {
                action = "<CMD>Lspsaga show_buf_diagnostics<Enter>";
                key = "<leader>cb";
              }
              {
                action = "<CMD>Lspsaga show_workspace_diagnostics<Enter>";
                key = "<leader>cw";
              }
            ];
          };
          servers = {
            bashls = {
              enable = true;
            };
            nixd = {
              enable = true;
              settings = {
                nixpkgs.expr = ''import (builtins.getFlake (toString ./.)).inputs.nixpkgs { }'';
                options = {
                  home_manager.expr = ''(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName}.options'';
                };
              };
            };
            pyright = {
              enable = true;
              settings = {
                python = {
                  analysis = {
                    typeCheckingMode = "basic";
                    autoSearchPaths = true;
                    useLibraryCodeForTypes = true;
                  };
                };
              };
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
              {name = "copilot";}
              {name = "nvim_lsp";}
              {name = "luasnip";}
              {name = "path";}
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
        copilot-lua = {
          enable = true;
        };
        copilot-cmp = {
          enable = true;
        };
        avante = {
          enable = true;
          settings = {
            provider = "copilot";
            providers.copilot.model = "claude-sonnet-4";
            windows = {
              wrap = true;
              input = {
                height = 15;
              };
              edit = {
                border = "rounded";
              };
            };
          };
        };
        lspkind = {
          enable = true;
          mode = "symbol";
          symbolMap = {
            Copilot = "";
          };
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
        lspsaga = {
          enable = true;
          lightbulb.enable = false;
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
        aerial = {
          enable = true;
          settings = {
            backends = ["treesitter" "lsp"];
          };
        };
        conform-nvim = {
          enable = true;
          settings = {
            formatters_by_ft = {
              python = ["black"];
              bash = ["shfmt"];
              nix = ["alejandra"];
              cpp = ["clang-format"];
              "_" = [
                "squeeze_blanks"
                "trim_whitespace"
                "trim_newlines"
              ];
            };
          };
        };
      };
      keymaps = [
        {
          mode = "n";
          key = "<leader>A";
          action = "<cmd>AerialToggle<CR>";
          options.desc = "Toggle aerial window";
        }
        {
          mode = "n";
          key = "<leader>cf";
          action = "<cmd>lua require('conform').format()<CR>";
          options.desc = "Format buffer with conform";
        }
      ];
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
