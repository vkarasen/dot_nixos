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
    ./sops.nix
    ./tmux
    ./neovim
    ./lf
  ];

  config = {
    home.stateVersion = "24.11";
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
