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
    ./lf.nix
  ];

  config = {
    home.stateVersion = "24.05";
    home.username = "vkarasen";
    home.homeDirectory = "/home/vkarasen";
    xdg.enable = true;

    catppuccin = {
      enable = true;
      flavor = "mocha";
    };
  };
}
