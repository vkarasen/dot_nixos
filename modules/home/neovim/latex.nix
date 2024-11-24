{pkgs, ...}: {
  config = {
    programs.nixvim = {
      plugins.vimtex = {
        enable = true;
        settings = {
          view_method = "zathura";
        };
        texlivePackage = null;
      };
    };
  };
}
