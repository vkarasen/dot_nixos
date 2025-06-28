{...}: {
  programs = {
    nixvim = {
      plugins = {
        telescope = {
          enable = true;
          keymaps = {
            "<leader>ff" = "find_files";
            "<leader>fg" = "live_grep";
            "<leader>fb" = "buffers";
            "<leader>fh" = "help_tags";
            "<leader>fo" = "oldfiles";
            "<leader>fs" = "lsp_document_symbols";
          };
          settings = {
            pickers = {
              oldfiles = {
                initial_mode = "normal";
              };
              buffers = {
                sort_lastused = true;
                sort_mru = true;
                initial_mode = "normal";
                mappings = {
                  n = {
                    "dd".__raw = "require('telescope.actions').delete_buffer";
                    "<c-h>".__raw = "function(bn) require('telescope.actions').extensions.file_browser.actions.toggle_hidden(bn) end";
                  };
                };
              };
            };
            defaults = {
              path_display = ["truncate"];
            };
          };
          extensions = {
            fzf-native.enable = true;
            live-grep-args.enable = true;
            advanced-git-search = {
              enable = true;
              settings = {
                diff_plugin = "diffview";
              };
            };
          };
        };
      };
    };
  };
}
