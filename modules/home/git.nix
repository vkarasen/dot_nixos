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
        };
        pull = {
          rebase = true;
        };
        init = {
          defaultBranch = "main";
        };
        pager = {
          difftool = "true";
        };
      };
    };
  };
}
