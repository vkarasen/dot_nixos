# Base home-manager configuration and custom options for user vkarasen
# Exports: flake.modules.homeManager.common
{ ... }: {
  flake.modules.homeManager.common = { config, lib, pkgs, ... }: {
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
        default =
          let
            user = builtins.getEnv "USER";
          in
            if user != ""
            then user
            else "vkarasen";
        description = "Name of the home configuration to use for LSP settings";
      };
    };

    config = {
      home = {
        stateVersion = "24.11";
        username = "vkarasen";
        homeDirectory = "/home/vkarasen";
        sessionPath = [ "~/.nix-profile/bin" ];
      };

      xdg.enable = true;

      xdg.configFile."nix/nix.conf" = {
        enable = true;
        text = ''
          experimental-features = nix-command flakes
        '';
      };

      programs.home-manager.enable = true;
    };
  };
}

