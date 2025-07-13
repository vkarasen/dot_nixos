{pkgs, ...}: {
  config = {
    home.packages = with pkgs; [
      tmux
    ];

    catppuccin.tmux.extraConfig =
      #tmux
      ''
        set -g @catppuccin_window_status_style "rounded"
        set -g status-right-length 100
        set -g status-left ""
        set -g status-right "#{E:@catppuccin_status_application}"
        set -ag status-right "#{E:@catppuccin_status_session}"
        set -g @catppuccin_window_current_text "#W"
        set -g @catppuccin_window_default_text "#W"
        set -g @catppuccin_window_text "#W"
      '';

    programs = {
      tmux = {
        enable = true;
        clock24 = true;
        historyLimit = 10000;
        prefix = "^A";
        keyMode = "vi";
        newSession = true;
        mouse = true;
        terminal = "screen-256color";

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
