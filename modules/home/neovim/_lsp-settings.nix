# Protocol-level LSP initializationOptions — no editor wrapper.
# Each consumer applies its own wrapping convention:
#   - rustaceanvim:  settings.server.default_settings."rust-analyzer" = lspSettings.rustAnalyzer
#   - nixvim lspconfig: plugins.lsp.servers.<name>.settings = lspSettings.<name>
#   - pi-lens (.pi-lens.json): serverOverrides.<id>.initializationOptions = lspSettings.<name>
#
# Imported by:
#   modules/_nixvim/lsp.nix            (nixvim plugin wiring; also used by standalone packages.nvim build)
#   modules/home/neovim/default.nix    (.pi-lens.json generation, full nixd settings)
#
# To add a new server with shared settings:
#   1. Add an attrset here (protocol-level options only, no editor-specific wrapper)
#   2. modules/_nixvim/lsp.nix: set  settings = lspSettings.<name>;  on the server entry
#   3. modules/home/neovim/default.nix: add  <pi-id>.initializationOptions = lspSettings.<name>;
#      to the serverOverrides block. Pi-lens server IDs: "rust", "nix", "bash", "python".
{
  rustAnalyzer = {
    check = {
      command = "clippy";
      allTargets = true;
    };
    diagnostics.styleLints.enable = true;
    imports.preferPrelude = true;
    inlayHints = {
      closureCaptureHints.enable = true;
      closureReturnTypeHints.enable = true;
      genericParameterHints.enable = true;
      parameterHints.missingArguments.enable = true;
    };
    interpret.tests = true;
    cargo = {
      features = "all";
      targetDir = true;
    };
    assist.preferSelf = true;
    files = {
      watcher = "server";
      exclude = [
        "**/.git/**"
        "**/target/**"
        "**/node_modules/**"
        "**/dist/**"
        "**/out/**"
      ];
    };
  };

  # Pyright (Python) — matches pi-lens server id "python".
  pyright = {
    python.analysis = {
      typeCheckingMode = "basic";
      autoSearchPaths = true;
      useLibraryCodeForTypes = true;
    };
  };

  # Base nixd settings without the per-machine home_manager.expr.
  # That expression references config.my.homeConfigurationName, which is only
  # available in the home-manager evaluation context.  The full options block is
  # assembled in modules/home/neovim/default.nix and merged back into nixvim.
  # NOTE: _nixvim/lsp.nix is also imported by the standalone packages.nvim build,
  # which has no HM context — that is why the split exists.
  nixdBase = {
    nixpkgs.expr = "import <nixpkgs> {}";
    options.nixvim.expr = "(builtins.getFlake (toString ./.)).nixVimOptions";
  };
}
