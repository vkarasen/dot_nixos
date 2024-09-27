{pkgs, ...}: let
  fzf_default_cmd = "fd --hidden --strip-cwd-prefix --exclude .git";
in {
  config = {
    home.packages = with pkgs; [
      nh
      nix-output-monitor
      nix-prefetch-git
      nvd
      ripgrep
      curl
      wget
      bat
      gnused
      tig
      dua
      duf
      fd
      tldr
    ];

    programs = {
      fzf = {
        enable = true;
        defaultCommand = fzf_default_cmd;
        changeDirWidgetCommand = fzf_default_cmd + " --type=d";
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
