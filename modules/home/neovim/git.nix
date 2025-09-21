{pkgs, ...}: {
  programs.nixvim = {
    plugins = {
      neogit = {
        enable = true;
      };
      gitsigns.enable = true;
      diffview.enable = true;
      octo = {
        enable = true;
      };
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
