{pkgs, ...}: {
  home.packages = with pkgs.python312Packages; [
    pylatexenc
  ];
  programs = {
    nixvim = {
      plugins = {
        lsp.servers.marksman = {
          enable = true;
        };
        markdown-preview = {
          enable = true;
        };
        render-markdown = {
          enable = true;
        };
      };
    };
  };
}
