# LaTeX support: VimTeX with Zathura
# Exports: flake.modules.nixvim.latex
{ ... }: {
  flake.modules.nixvim.latex = { ... }: {
    plugins.vimtex = {
      enable = true;
      settings = {
        view_method = "zathura";
      };
      texlivePackage = null;
    };
  };
}

