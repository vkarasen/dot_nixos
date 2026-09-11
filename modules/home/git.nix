# Dendritic aspect: git (home-manager class).
{...}: {
  flake.modules.homeManager.git = {
    pkgs,
    config,
    lib,
    ...
  }: let
    # Editor wrapper: under pi (detected via the process markers every pi child
    # inherits) the editor is a no-op, so git never blocks on an interactive
    # editor (commit / rebase --continue / reword messages). Outside pi it
    # falls through to the normal editor ($VISUAL -> $EDITOR -> vi).
    pi-aware-editor = pkgs.writeShellScriptBin "pi-aware-editor" ''
      if [ -n "$PI_CODING_AGENT" ] || [ "$AI_AGENT" = "pi" ]; then
        exit 0
      fi
      ed="$VISUAL"
      [ -z "$ed" ] && ed="$EDITOR"
      [ -z "$ed" ] && ed="vi"
      exec "$ed" "$@"
    '';
  in {
    config = {
      home.packages = with pkgs; [
        delta
        pi-aware-editor
      ];

      programs = {
        gh = {
          enable = true;
          gitCredentialHelper = {
            enable = true;
          };
          extensions = lib.optionals config.my.copilot.enable [
            pkgs.github-copilot-cli
          ];
        };
        mergiraf = {
          enable = true;
          enableGitIntegration = true;
        };
        git = {
          enable = true;

          ignores = [
            ".envrc"
            ".direnv/"
            ".worktrees/"
            ".git"
          ];

          settings = {
            alias = {
              reset-upstream = "reset --hard @{u}";
            };
            user = {
              email = config.my.git.email;
              name = "Vitali Karasenko";
            };
            core = {
              pager = "delta";
              editor = "${pi-aware-editor}/bin/pi-aware-editor";
              fsmonitor = true;
              untrackedCache = true;
              compression = 9;
              whitespace = "error";
              preloadindex = true;
            };
            sequence = {
              editor = "${pi-aware-editor}/bin/pi-aware-editor";
            };
            interactive = {
              diffFilter = "delta --color-only";
            };
            delta = {
              navigate = true;
              features = "side-by-side line-numbers decorations";
              syntax-theme = "Catppuccin Mocha";
            };
            diff = {
              colorMoved = "default";
              algorithm = "histogram";
              mnemonicPrefix = true;
              renames = true;
            };
            pull = {
              rebase = true;
            };
            rebase = {
              autoSquash = true;
              autoStash = true;
              updateRefs = true;
              missingCommitsCheck = "warn";
            };
            push = {
              autoSetupRemote = true;
              followTags = true;
            };
            fetch = {
              prune = true;
              pruneTags = true;
              all = true;
            };
            init = {
              defaultBranch = "main";
            };
            help = {
              autocorrect = "prompt";
            };
            rerere = {
              enabled = true;
              autoupdate = true;
            };
            pager = {
              difftool = "true";
            };
            column = {
              ui = "auto";
            };
            branch = {
              sort = "-committerdate";
            };
            tag = {
              sort = "version:refname";
            };
          };
        };
      };
    };
  };
}
