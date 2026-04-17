# Markdown support: marksman LSP, preview, rendering
# Exports: flake.modules.nixvim.markdown
{ ... }: {
  flake.modules.nixvim.markdown = { ... }: {
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
}

