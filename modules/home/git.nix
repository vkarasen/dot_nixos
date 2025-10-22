{
  pkgs,
  config,
  lib,
  ...
}: {
  config = {
    home.packages = with pkgs; [
      delta
    ];

    programs = {
      gh = {
        enable = true;
        gitCredentialHelper = {
          enable = true;
        };
        extensions = lib.optionals config.nixpkgs.config.allowUnfree [
          pkgs.gh-copilot
        ];
      };
      git = {
        enable = true;

        settings = {
          user = {
            email = config.my.git.email;
            name = "Vitali Karasenko";
          };
          core = {
            pager = "delta";
            fsmonitor = true;
            untrackedCache = true;
            compression = 9;
            whitespace = "error";
            preloadindex = true;
          };
          interactive = {
            diffFilter = "delta --color-only";
          };
          delta = {
            navigate = true;
            features = "side-by-side line-numbers decorations";
            syntax-theme = "Catppuccin Mocha";
          };
          merge = {
            conflictstyle = "zdiff3";
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
}
