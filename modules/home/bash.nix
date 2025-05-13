{
  pkgs,
  config,
  lib,
  ...
}: let
  bashprivate =
    if config.my.is_private
    then "eval $(ssh-agent)"
    else "";
in {
  config = {
    home.packages = with pkgs; [
      fzf-git-sh
    ];

    programs = {
      bash = {
        enable = true;
        enableCompletion = true;
        historySize = 10000;
        historyControl = ["ignoreboth"];

        initExtra =
          lib.strings.concatLines
          [
            bashprivate
            #bash
            ''
              set -o vi

              source ${pkgs.fzf-git-sh}/share/fzf-git-sh/fzf-git.sh

              eval "$(batpipe)"
              eval "$(batman --export-env)"
            ''
          ];

        shellAliases = {
          cat = "bat";

          grep = "rg";

          cd = "z";

          #lists only directories (no files)
          ldo = "eza -lD";

          #lists only files (no directories)
          lfo = "eza -lf --color=always";

          #lists only hidden files (no directories)
          lho = "eza -dl .* --group-directories-first";

          #lists everything with directories first
          ll = "eza -al --group-directories-first";

          ls = "eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions";

          #lists everything sorted by time updated
          lt = "eza -al --sort=modified";
        };
      };

      fzf = {
        enableBashIntegration = true;
      };

      zoxide = {
        enableBashIntegration = true;
      };

      starship = {
        enableBashIntegration = true;
        settings = {
          add_newline = false;
        };
      };
      carapace = {
        enableBashIntegration = true;
        enable = true;
      };
      eza = {
        enableBashIntegration = true;
        git = true;
      };

      direnv = {
        enableBashIntegration = true;
      };
    };
  };
}
