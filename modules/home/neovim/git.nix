{pkgs, ...}: {
  programs.nixvim = {
    plugins = {
      neogit = {
        enable = true;
        package = pkgs.stable.vimPlugins.neogit;
      };
      gitsigns.enable = true;
      diffview.enable = true;
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
