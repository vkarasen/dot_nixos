{...}: {
  plugins = {
    lsp.servers.marksman = {
      # issues with lspsaga, disabling for now
      enable = false;
    };
    markdown-preview = {
      enable = true;
      lazyLoad.settings = {
        cmd = ["MarkdownPreview" "MarkdownPreviewStop" "MarkdownPreviewToggle"];
        ft = "markdown";
      };
    };
    render-markdown = {
      enable = true;
      lazyLoad.settings.ft = ["markdown" "Avante"];
    };
  };
}
