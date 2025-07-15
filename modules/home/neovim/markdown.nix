{pkgs, ...}: {
  home.packages = with pkgs.python312Packages; [
    pylatexenc
  ];
  programs = {
    nixvim = {
      plugins = {
        lsp.servers.marksman = {
          # issues with lspsaga, disabling for now
          enable = false;
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
