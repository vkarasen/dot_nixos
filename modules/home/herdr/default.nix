# Dendritic aspect: herdr (home-manager class).
{inputs, ...}: {
  flake.modules.homeManager.herdr = {
    pkgs,
    lib,
    config,
    ...
  }: let
    # Mechanism B (primary cleanup path, see my.worktrunk.autoPrune doc for
    # mechanism A, the backstop): a local herdr plugin that prunes the git
    # worktree behind a herdr sub-workspace the moment it's closed, iff
    # Worktrunk independently considers it merged. See
    # plugins/worktrunk-close-prune/on-workspace-closed.sh for the safety
    # reasoning; the script itself is the source of truth, this just wraps
    # it with an absolute-path PATH so it works regardless of what PATH the
    # long-running herdr server process happened to start with.
    worktrunkClosePruneScript = pkgs.writeShellApplication {
      name = "on-workspace-closed";
      runtimeInputs = [pkgs.jq pkgs.worktrunk pkgs.git];
      text = builtins.readFile ./plugins/worktrunk-close-prune/on-workspace-closed.sh;
    };
    worktrunkClosePrunePlugin = pkgs.runCommand "herdr-plugin-worktrunk-close-prune" {} ''
      mkdir -p $out
      cp ${./plugins/worktrunk-close-prune/herdr-plugin.toml} $out/herdr-plugin.toml
      ln -s ${worktrunkClosePruneScript}/bin/on-workspace-closed $out/on-workspace-closed
    '';

    # Standalone one-shot CLI: relocate misplaced pi tabs into their correct
    # herdr workspace and repair hijacked/mis-rooted worktree workspaces
    # (logic in organize/herdr-organize.js). Wrapped with an
    # absolute node shebang so it needs no node on PATH at runtime; the .js is
    # the source of truth, this just makes it an executable on PATH.
    herdrOrganize = pkgs.writeTextFile {
      name = "herdr-organize";
      executable = true;
      destination = "/bin/herdr-organize";
      text = "#!${pkgs.nodejs}/bin/node\n" + builtins.readFile ./organize/herdr-organize.js;
    };

    # Sole owner of the `tab.move` socket protocol (there is no CLI wrapper):
    # move a herdr tab to a position via the socket API (logic in
    # tab-move/tab-move.js). Reordering is cosmetic, so callers treat failure
    # as non-fatal. Wrapped with an absolute node shebang like herdrOrganize.
    tabMove = pkgs.writeTextFile {
      name = "herdr-tab-move";
      executable = true;
      destination = "/bin/herdr-tab-move";
      text = "#!${pkgs.nodejs}/bin/node\n" + builtins.readFile ./tab-move/tab-move.js;
    };
  in {
    programs.herdr = {
      enable = true;

      settings = {
        onboarding = lib.mkDefault false;

        terminal = {
          shell_mode = "auto";
          new_cwd = "follow";
        };

        theme.name = lib.mkDefault "catppuccin";

        ui.show_agent_labels_on_pane_borders = lib.mkDefault true;
        ui.sidebar_width = lib.mkDefault 32;
        ui.toast.delivery = lib.mkDefault "herdr";
        ui.toast.herdr.position = lib.mkDefault "bottom-right";
        ui.sound.enabled = lib.mkDefault true;

        # Deliberate SIBLING of worktrunk's own root (modules/home/worktrunk.nix),
        # never the same directory, so the two independent worktree-creation
        # mechanisms can't collide. Derived from the same shared option so
        # they can't drift apart; see my.worktrunk.worktreeRoot's doc comment.
        worktrees.directory = lib.mkDefault "${config.my.worktrunk.worktreeRoot}/.herdr-worktrees";

        keys.prefix = "ctrl+a";
        # `new_worktree` (create) already ships bound to prefix+shift+g.
        # These two round out the worktree action set that new_worktree came
        # with unbound by default:
        #   - open_worktree: open a picker of EXISTING worktrees and reattach
        #     a sub-workspace to the chosen one — the recovery path after an
        #     accidental close. NOTE (verified against herdr source): like
        #     new_worktree, it must be invoked from the repo PARENT workspace,
        #     not from inside a linked worktree sub-workspace (where it errors
        #     with "New and open worktree actions start from the repo parent
        #     workspace."). "o" mirrors vim's open-line mnemonic and pairs
        #     with new_worktree's shift+g.
        #   - remove_worktree: delete a worktree checkout (opens a confirmation
        #     dialog; never deletes the branch). "e" for erase; kept off the
        #     x/shift+x pane/tab-close ladder since this is more permanent.
        keys.open_worktree = lib.mkDefault "prefix+shift+o";
        keys.remove_worktree = lib.mkDefault "prefix+shift+e";
      };
    };

    home.packages = [pkgs.herdr herdrOrganize tabMove];

    # Run `herdr integration install pi` on every home-manager activation.
    # Herdr handles idempotency itself; we just ensure the target directory
    # exists first because herdr requires it to be present.
    # Respects PI_CODING_AGENT_DIR if set (herdr reads the same var).
    home.activation.herdrPiIntegration = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _pi_dir="''${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
      $DRY_RUN_CMD mkdir -p "$_pi_dir/extensions"
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr integration install pi
    '';

    # Link + enable the local worktrunk-close-prune plugin on every
    # activation. `herdr plugin link` re-points the registration at this
    # generation's (possibly new) nix store path each time the script
    # changes, and `--enabled` keeps it active without a separate enable
    # call; both link and install work with no server running.
    home.activation.herdrWorktrunkClosePrunePlugin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.herdr}/bin/herdr plugin link ${worktrunkClosePrunePlugin} --enabled
    '';
  };
}
