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
        newSession = true;

        plugins = with pkgs.tmuxPlugins; [
          sensible
          yank
          tmux-fzf
        ];

        extraConfig =
          #tmux
          ''
            set -g base-index 1
            set -g renumber-windows on
            bind f run -b "${pkgs.tmuxPlugins.tmux-fzf}/share/tmux-plugins/tmux-fzf/scripts/window.sh switch"
          '';
      };

      fzf.tmux.enableShellIntegration = true;
    };
  };
}
