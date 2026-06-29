{...}: {
  plugins = {
    neogit = {
      enable = true;
      lazyLoad.settings.cmd = "Neogit";
    };
    gitsigns.enable = true;
    diffview = {
      enable = true;
      lazyLoad.settings.cmd = [
        "DiffviewOpen"
        "DiffviewClose"
        "DiffviewFileHistory"
        "DiffviewFocusFiles"
        "DiffviewToggleFiles"
      ];
    };
    octo = {
      enable = true;
      lazyLoad.settings.cmd = "Octo";
    };
  };
  keymaps = [
    {
      mode = "n";
      key = "<leader>ng";
      action = ":Neogit<cr>";
    }
  ];
}
