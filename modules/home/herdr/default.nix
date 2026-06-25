# Dendritic aspect: herdr (home-manager class).
{ inputs, ... }: {
  flake.modules.homeManager.herdr = { pkgs, lib, config, ... }: {
    imports = [ ./_module.nix ];

    programs.herdr = {
      enable = true;

      settings = {
        onboarding = lib.mkDefault false;

        terminal = {
          shell_mode = "auto";
          new_cwd = "follow";
        };

        theme.name = lib.mkDefault "catppuccin";

        # Show agents across ALL workspaces, not just the active one —
        # this is the key setting for multi-project visibility.
        ui.agent_panel_scope = lib.mkDefault "all";
        ui.show_agent_labels_on_pane_borders = lib.mkDefault true;
        ui.sidebar_width = lib.mkDefault 32;
        ui.toast.delivery = lib.mkDefault "herdr";
        ui.toast.herdr.position = lib.mkDefault "bottom-right";
        ui.sound.enabled = lib.mkDefault true;
        keys.prefix = "ctrl+a";
      };
    };

    home.packages = [ pkgs.herdr ];

    # Run `herdr integration install pi` on every home-manager activation.
    # Herdr handles idempotency itself; we just ensure the target directory
    # exists first because herdr requires it to be present.
    # Respects PI_CODING_AGENT_DIR if set (herdr reads the same var).
    home.activation.herdrPiIntegration =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _pi_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
        $DRY_RUN_CMD mkdir -p "$_pi_dir/extensions"
        $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install pi
      '';
  };
}
