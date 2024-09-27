{
  lib,
  pkgs,
  ...
}: {
  config = {
    home.packages = with pkgs; [
      tmux
    ];

    programs = {
      tmux = {
        enable = true;
        clock24 = true;
        historyLimit = 10000;
        prefix = "^A";
        keyMode = "vi";

        plugins = with pkgs.tmuxPlugins; [
          sensible
          yank
          tmux-fzf
        ];

        extraConfig = ''
          set -g base-index 1
          set -g renumber-windows on
        '';
      };

      fzf.tmux.enableShellIntegration = true;
    };
  };
}
