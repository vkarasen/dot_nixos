{...}: {
  programs = {
    nixvim = {
      plugins = {
        lsp.servers.marksman = {
          enable = true;
        };
        markdown-preview = {
          enable = true;
        };
      };
    };
  };
}
