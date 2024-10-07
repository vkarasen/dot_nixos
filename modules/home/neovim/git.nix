{...}: {
  programs.nixvim = {
    plugins = {
      neogit.enable = true;
      gitsigns.enable = true;
      diffview.enable = true;
      web-devicons.enable = true;
    };
    keymaps = [
      {
        mode = "n";
        key = "<leader>ng";
        action = ":Neogit<cr>";
      }
    ];
  };
}
