{
  options,
  config,
  lib,
  pkgs,
  optnix,
  ...
}: let
  optnixLib = optnix.mkLib pkgs;
in {
  programs.optnix = {
    enable = true;
    settings = {
      default_scope = "home-manager";
      scopes.home-manager = {
        description = "home-manager configuration for vkarasen";
        options-list-file = optnixLib.mkOptionsList {
          inherit options;
          transform = o:
            o
            // {
              name = lib.removePrefix "home-manager.users.${config.home.username}." o.name;
            };
        };
        evaluator = "";
      };
    };
  };
}

