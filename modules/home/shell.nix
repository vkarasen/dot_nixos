# Shell environment: bash, CLI packages, and integrations
# Exports: flake.homeModules.shell
{ ... }: {
  flake.homeModules.shell = { pkgs, config, lib, ... }:
  let
    bashprivate =
      if config.my.is_private or false
      then "eval $(ssh-agent)"
      else "";
  in
  {
    home.packages = with pkgs; [
      nh
      nix-output-monitor
      nix-prefetch-git
      nix-search-cli
      nvd
      ripgrep
      curl
      wget
      bat
      gnused
      dua
      duf
      dutree
      fd
      tldr
      yq
      jq
      patool
      sd
      file
      openssl
      ncurses
      tabiew
    ];

    home.sessionVariables = {
      BATDIFF_USE_DELTA = "true";
    };

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
            ''
              set -o vi

              bind 'set show-mode-in-prompt on'
              bind 'set vi-cmd-mode-string "\1\e[2 q\2"'
              bind 'set vi-ins-mode-string "\1\e[6 q\2"'

              eval "$(batpipe)"
              eval "$(batman --export-env)"
            ''
          ];

        shellAliases = {
          tw = "tw --theme catppuccin";
          cat = "bat";
          grep = "rg";
          cd = "z";

          # lists only directories (no files)
          ldo = "eza -lD";

          # lists only files (no directories)
          lfo = "eza -lf --color=always";

          # lists only hidden files (no directories)
          lho = "eza -dl .* --group-directories-first";

          # lists everything with directories first
          ll = "eza -al --group-directories-first";

          ls = "eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions";

          # lists everything sorted by time updated
          lt = "eza -al --sort=modified";
        };
      };

      atuin = {
        enable = true;
        enableBashIntegration = true;
        daemon.enable = true;
        settings = {
          auto_sync = false;
          style = "auto";
          dialect = "uk";
          filter_mode_shell_up_key_binding = "workspace";
          keymap_mode = "auto";
          update_check = false;
          workspaces = true;
          enter_accept = true;
        };
      };

      zoxide = {
        enable = true;
        enableBashIntegration = true;
      };

      starship = {
        enable = true;
        enableBashIntegration = true;
        settings = {
          add_newline = false;

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
        enable = true;
        enableBashIntegration = true;
        git = true;
      };

      direnv = {
        enable = true;
        enableBashIntegration = true;
        nix-direnv.enable = true;
      };

      fzf = rec {
        enable = true;
        defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git";
        changeDirWidgetCommand = defaultCommand + " --type=d";
      };

      bat = {
        enable = true;
        config = {
          theme = "Catppuccin Mocha";
        };
        extraPackages = with pkgs.bat-extras; [batdiff batwatch batpipe batman batgrep];
      };
    };
  };
}

