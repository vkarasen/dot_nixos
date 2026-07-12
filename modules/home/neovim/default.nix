# Dendritic aspect: neovim (home-manager class).
{...}: {
  flake.modules.homeManager.neovim = {config, lib, ...}: let
    # Shared protocol-level LSP settings (defined once, used by nixvim + pi-lens).
    lspSettings = import ./_lsp-settings.nix;

    # Full nixd settings: base (from _lsp-settings.nix) + home_manager option
    # expression that references this machine's HM configuration name.
    nixdFull = lib.recursiveUpdate lspSettings.nixdBase {
      options.home_manager.expr = "(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName}.options";
    };
  in {
    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins.lsp.servers.nixd.settings = nixdFull;

      imports = [
        ../../_nixvim
      ];
    };

    # Generate .pi-lens.json so pi-lens picks up the same LSP initializationOptions
    # as vim when running inside ~/nix/dot_nixos/.
    # pi-lens walks up from cwd to find the config file, so placing it at the repo
    # root is sufficient. Server IDs match pi-lens's built-in ids (see server.js).
    home.file."nix/dot_nixos/.pi-lens.json".text = builtins.toJSON {
      serverOverrides = {
        rust.initializationOptions = lspSettings.rustAnalyzer;
        nix.initializationOptions = nixdFull;
        python.initializationOptions = lspSettings.pyright;
      };
    };
  };
}
