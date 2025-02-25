{
  lib,
  pkgs,
  ...
}: {
  config = {
    home.packages = with pkgs; [
      delta
    ];

    programs.git = {
      enable = true;

      userEmail = "vkarasen@gmail.com";
      userName = "Vitali Karasenko";

      extraConfig = {
        core = {
          pager = "delta";
          fsmonitor = true;
          untrackedCache = true;
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
          conflictstyle = "diff3";
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
}
