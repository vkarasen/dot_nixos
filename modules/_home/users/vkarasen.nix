{ lib, ... }:
{
  imports = [
    ../options.nix
    ../base.nix
    ../collections/development.nix
    ../collections/security.nix
    ../aspects/terminal/tmux.nix
  ];

  config = {
    # Catppuccin theme configuration handled at flake level
    # catppuccin = {
    #   enable = true;
    #   flavor = "mocha";
    # };
  };
}

