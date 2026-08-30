{...}: {
  plugins = {
    telescope = {
      enable = true;
      # All picker keymaps invoke `:Telescope ...` commands, so a cmd trigger is
      # sufficient and moves setup + extension loading out of startup.
      lazyLoad.settings.cmd = "Telescope";
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
          find_files = {
            hidden = true;
          };
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
      };
    };
  };
}
