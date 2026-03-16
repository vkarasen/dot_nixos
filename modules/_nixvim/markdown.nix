{...}: {
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
}
