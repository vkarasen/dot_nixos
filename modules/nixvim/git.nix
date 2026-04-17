# Git integration: neogit, gitsigns, diffview, octo
# Exports: flake.modules.nixvim.git
{ ... }: {
  flake.modules.nixvim.git = { ... }: {
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

