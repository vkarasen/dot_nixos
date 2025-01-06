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
          };
        };
        harpoon = {
          enable = true;
          enableTelescope = true;
          keymaps = {
            addFile = "<leader>ha";
            navNext = "<leader>hn";
            navPrev = "<leader>hp";
            toggleQuickMenu = "<leader>fp";
            cmdToggleQuickMenu = "<leader>fP";
          };
        };
      };
    };
  };
}
