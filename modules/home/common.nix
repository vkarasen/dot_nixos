# Base home-manager configuration and custom options
# Exports: flake.homeModules.common
{ ... }:
let
  constants = import ../_constants/users.nix;
  systemConstants = import ../_constants/system.nix;
in
{
  flake.homeModules.common = { config, lib, pkgs, ... }: {
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
        stateVersion = systemConstants.system.stateVersion;
        username = constants.users.primary.name;
        homeDirectory = constants.users.primary.homeDirectory;
        sessionPath = [ "~/.nix-profile/bin" ];
      };

      xdg.enable = true;

      xdg.configFile."nix/nix.conf" = {
        enable = true;
        text = ''
          experimental-features = ${lib.concatStringsSep " " systemConstants.system.experimentalFeatures}
        '';
      };

      programs.home-manager.enable = true;
    };
  };
}

