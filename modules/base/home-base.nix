{ config, lib, pkgs, ... }:
let
  constants = import ../constants/users.nix;
  systemConstants = import ../constants/system.nix;
in
{
  home = {
    stateVersion = systemConstants.system.stateVersion;
    username = constants.users.primary.name;
    homeDirectory = constants.users.primary.homeDirectory;
  };

  xdg.enable = true;

  xdg.configFile."nix/nix.conf" = {
    enable = true;
    text = ''
      experimental-features = ${lib.concatStringsSep " " systemConstants.system.experimentalFeatures}
    '';
  };

  catppuccin = {
    enable = true;
    flavor = systemConstants.catppuccin.flavor;
  };

  programs.home-manager.enable = true;
  home.sessionPath = [ "~/.nix-profile/bin" ];
}

