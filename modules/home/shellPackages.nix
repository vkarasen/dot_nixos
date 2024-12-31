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
      fd
      tldr
      yq
      jq
      stable.patool
      sd
      file
      openssl
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
        themes = {
          catppuccin-mocha = {
            src = pkgs.fetchFromGitHub {
              owner = "catppuccin";
              repo = "bat";
              rev = "d3feec47b16a8e99eabb34cdfbaa115541d374fc";
              sha256 = "1g73x0p8pbzb8d1g1x1fwhwf05sj3nzhbhb65811752p5178fh5k";
            };
            file = "themes/Catppuccin Mocha.tmTheme";
          };
        };
        config = {
          theme = "Catppuccin Mocha";
        };
      };
    };
  };
}
