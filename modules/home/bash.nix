# Dendritic aspect: bash (home-manager class).
{...}: {
  flake.modules.homeManager.bash = {
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

                bind 'set show-mode-in-prompt on'
                bind 'set vi-cmd-mode-string "\1\e[2 q\2"'
                bind 'set vi-ins-mode-string "\1\e[6 q\2"'

                eval "$(batpipe)"
                eval "$(batman --export-env)"

                eval "$(wt config shell init bash)"
              ''
              # Atuin history capture. Loaded via atuin's own bundled
              # bash-preexec (see the enableBashIntegration note above).
              ''
                eval "$(atuin init bash)"
                # Upstream intentionally leaves C-r unbound in vi-command mode (to
                # preserve redo), so C-r in normal mode falls through to readline's
                # native reverse-search-history. Bind it to atuin explicitly.
                atuin-bind -m vi-command '\C-r' atuin-search-vicmd
              ''
            ];

          shellAliases = {
            tw = "tw --theme catppuccin";
            cat = "bat";

            grep = "rg";

            cd = "z";

            gcd = "cd $(git rev-parse --show-toplevel 2>/dev/null)";

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

        atuin = {
          enable = true;
          # Disabled: HM's bash integration sources nixpkgs' bash-preexec
          # 0.6.0, whose __bp_install fails to strip its install string from
          # an array PROMPT_COMMAND (Bash >= 5.1), leaving `trap - DEBUG` to
          # run at every prompt and silently disabling history capture.
          # We eval `atuin init bash` manually in initExtra instead, which
          # uses atuin's own (fixed) bundled bash-preexec.
          enableBashIntegration = false;
          daemon.enable = true;
          settings = {
            auto_sync = false;
            style = "auto";
            dialect = "uk";
            # WORKAROUND: "workspace" collapses git worktrees to the main repo
            # (atuin PR #3366, since 18.14), so a worktree shows the main
            # checkout's history. "directory" (exact cwd) is the closest
            # supported filter in 18.19.0; we still want a true per-worktree
            # filter — see atuinsh/atuin#3819.
            filter_mode_shell_up_key_binding = "directory";
            keymap_mode = "auto";
            update_check = false;
            workspaces = true;
            enter_accept = true;
          };
        };

        zoxide = {
          enableBashIntegration = true;
        };

        starship = {
          enableBashIntegration = true;
          settings = {
            add_newline = false;

            # Catppuccin mocha (applied to the base prompt modules).
            directory.style = "bold #89b4fa";
            directory.truncation_length = 3;
            git_branch.style = "bold #a6e3a1";
            git_status.style = "#f38ba8";
            character = {
              success_symbol = "[❯](bold #a6e3a1)";
              error_symbol = "[❯](bold #f38ba8)";
            };
            time.style = "bold #a6adc8";

            # Custom herdr module — shows a green icon in shells outside herdr
            # whenever the herdr server is running.  Detection is socket-based
            # (the socket only exists while the server is up) so no herdr
            # subprocess is spawned on each prompt render.  Hidden inside
            # herdr panes (HERDR_ENV=1) where the context is already obvious.
            custom.herdr = {
              when = ''test -S "''${XDG_CONFIG_HOME:-$HOME/.config}/herdr/herdr.sock" && [ "$HERDR_ENV" != "1" ]'';
              symbol = "󱡃 ";
              style = "bold green";
            };

            # Custom tmux module
            custom.tmux = {
              command = "tmux list-sessions 2>/dev/null | wc -l";
              when = "test $(tmux list-sessions 2>/dev/null | wc -l) -gt 0 && test -z \"$TMUX\"";
              symbol = "󰗹 ";
              style = "bold blue";
            };

            status.disabled = false;
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
  };
}
