# Dendritic aspect: neovim (home-manager class).
{...}: {
  flake.modules.homeManager.neovim = {config, ...}: let
    # Shared protocol-level LSP settings (defined once, used by nixvim + pi-lens).
    s = import ./_lsp-settings.nix;

    # Full nixd settings: base (from _lsp-settings.nix) + home_manager option
    # expression that references this machine's HM configuration name.
    nixdFull =
      s.nixdBase
      // {
        options =
          s.nixdBase.options
          // {
            home_manager.expr = "(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName}.options";
          };
      };
  in {
    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      # Inject the full nixd settings here (where config.my.* is available).
      # _nixvim/lsp.nix only sets nixdBase; this merges in the missing home_manager
      # option expression via the nixvim module system.
      plugins.lsp.servers.nixd.settings = nixdFull;

      imports = [
        ../../_nixvim
      ];
    };

    # Generate .pi-lens.json for the fork of pi-lens that supports serverOverrides.
    # pi-lens walks up from cwd, so placing this at the repo root means it is
    # picked up when pi runs inside ~/nix/dot_nixos/.
    home.file."nix/dot_nixos/.pi-lens.json".text = builtins.toJSON {
      serverOverrides = {
        rust.initializationOptions = s.rustAnalyzer;
        nix.initializationOptions = nixdFull;
      };
    };
  };
}
