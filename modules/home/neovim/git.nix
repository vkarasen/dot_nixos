{...}: {
  programs.nixvim = {
    plugins = {
      neogit.enable = true;
      gitsigns.enable = true;
      diffview.enable = true;
      web-devicons.enable = true;
    };
  };
}
