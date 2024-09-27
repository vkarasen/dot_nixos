{
  lib,
  pkgs,
  ...
}: {
  config = {
    home.packages = with pkgs; [
	    fzf-git-sh
    ];

    programs = {
      bash = {
        enable = true;
        enableCompletion = true;
        historySize = 10000;

        initExtra = ''
          set -o vi
          HISTCONTROL='ignoreboth'

	  source ${pkgs.fzf-git-sh}/share/fzf-git-sh/fzf-git.sh
        '';

        shellAliases = {
          cat = "bat";

          grep = "rg";

          #lists only directories (no files)
          ld = "eza -lD";

          #lists only files (no directories)
          lf = "eza -lf --color=always";

          #lists only hidden files (no directories)
          lh = "eza -dl .* --group-directories-first";

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

      starship = {
        enableBashIntegration = true;
        settings = {
          add_newline = true;
        };
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
