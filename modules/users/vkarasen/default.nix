{ lib, ... }:
{
  imports = [
    ../../base/home-base.nix
    ../../collections/development.nix
    ../../collections/security.nix
    ../../aspects/terminal/tmux.nix
  ];

  # Custom options for this user configuration
  options.my = {
    is_private = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    git.email = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "vkarasen@gmail.com";
    };
    portable = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
      path = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "~/nix/nix-portable";
      };
    };
    homeConfigurationName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = let
        user = builtins.getEnv "USER";
      in
        if user != ""
        then user
        else "vkarasen";
      description = "Name of the home configuration to use for LSP settings";
    };
  };

  config = {
    # Catppuccin theme configuration handled at flake level
    # catppuccin = {
    #   enable = true;
    #   flavor = "mocha";
    # };
  };
}

