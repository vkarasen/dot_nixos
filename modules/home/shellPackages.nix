# Dendritic aspect: shellPackages (home-manager class).
{...}: {
  flake.modules.homeManager.shellPackages = {pkgs, ...}: {
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
        wl-clipboard
      ];

      programs = {
        fzf = rec {
          enable = true;
          defaultCommand = "fd --hidden --strip-cwd-prefix --exclude .git";
          changeDirWidget.command = defaultCommand + " --type=d";
          historyWidget.command = "";
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
          extraPackages = with pkgs.bat-extras; [batdiff batwatch batpipe batman batgrep];
        };
      };

      home.sessionVariables = {
        BATDIFF_USE_DELTA = "true";
      };
    };
  };
}
