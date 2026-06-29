{...}: {
  plugins.vimtex = {
    enable = true;
    lazyLoad.settings.ft = ["tex" "latex" "cls"];
    settings = {
      view_method = "zathura";
    };
    texlivePackage = null;
  };
}
