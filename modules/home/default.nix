{
  lib,
  config,
  ...
}: {
  imports = [
    ./shellPackages.nix
    ./ssh.nix
    ./git.nix
    ./bash.nix
    ./tmux
    ./neovim
  ];

  config = {
    home.stateVersion = "24.05";
    home.username = "vkarasen";
    home.homeDirectory = "/home/vkarasen";

    catppuccin = {
      enable = true;
      flavor = "mocha";
    };
  };
}
