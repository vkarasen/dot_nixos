{pkgs, ...}: {
  config = {
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
      stable.patool
      sd
      file
      openssl
      ncurses
    ];

    programs = {
      fzf = rec {
        enable = true;
        defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git";
        changeDirWidgetCommand = defaultCommand + " --type=d";
      };
      starship.enable = true;
      eza.enable = true;
      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      zoxide.enable = true;
      bat = {
        enable = true;
        config = {
          theme = "Catppuccin Mocha";
        };
        extraPackages = with pkgs.bat-extras; [batdiff batgrep batwatch batpipe batman];
      };
    };

    home.sessionVariables = {
      BATDIFF_USE_DELTA = "true";
    };
  };
}
