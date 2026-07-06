# Protocol-level LSP settings — no editor wrapper.
# Each consumer applies its own wrapping convention:
#   - rustaceanvim:  default_settings."rust-analyzer" = rustAnalyzer
#   - nixvim lspconfig: settings = nixdBase  (lspconfig wraps under "nixd" key)
#   - pi-lens (.pi-lens.json): serverOverrides.<id>.initializationOptions = <value>
#
# Imported by:
#   modules/_nixvim/lsp.nix            (nixvim plugin wiring, standalone nvim build)
#   modules/home/neovim/default.nix    (.pi-lens.json generation, full nixd settings)
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

  # Base nixd settings without the per-machine home_manager.expr.
  # That expression references config.my.homeConfigurationName, which is only
  # available in the home-manager evaluation context.  The full options block is
  # assembled in modules/home/neovim/default.nix and merged back into nixvim.
  nixdBase = {
    nixpkgs.expr = "import <nixpkgs> {}";
    options.nixvim.expr = "(builtins.getFlake (toString ./.)).nixVimOptions";
  };
}
