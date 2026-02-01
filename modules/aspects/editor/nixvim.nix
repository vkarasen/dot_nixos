{ config, ... }:
{
  programs = {
    nixvim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins.nixd.settings.options.home_manager.expr = ''(builtins.getFlake (toString ./.)).homeConfigurations.${config.my.homeConfigurationName or "vkarasen"}.options'';

      imports = [
        ../../base/nixvim-base.nix
        ../../../nixvim
      ];
    };
  };
}

