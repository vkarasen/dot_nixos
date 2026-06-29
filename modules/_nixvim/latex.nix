{...}: {
  plugins.vimtex = {
    enable = true;
    lazyLoad.settings.ft = ["tex" "cls"];
    settings = {
      view_method = "zathura";
    };
    texlivePackage = null;
  };
}
