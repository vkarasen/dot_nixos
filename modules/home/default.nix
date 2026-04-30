{
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./shellPackages.nix
    ./ssh.nix
    ./git.nix
    ./bash.nix
    ./sops
    ./tmux
    ./neovim
    ./lf
    ./opencode
  ];

  config = {
    home.stateVersion = "26.05";
    home.username = "vkarasen";
    home.homeDirectory = "/home/vkarasen";
    xdg.enable = true;

    xdg.configFile."nix/nix.conf" = {
      enable = true;
      text =
        #nix
        ''
          experimental-features = nix-command flakes
        '';
    };

    catppuccin = {
      enable = true;
      flavor = "mocha";
    };
  };
}
