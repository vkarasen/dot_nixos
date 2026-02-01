{ pkgs, config, lib, ... }:
{
  home.packages = with pkgs; [
    openssh
  ];

  services.ssh-agent.enable = config.my.is_private or false;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      "*" = {
        addKeysToAgent =
          if config.my.is_private or false
          then "yes"
          else "no";
      };
      github = {
        hostname = "github.com";
        user = "git";
        # identityFile = "~/.ssh/id_ed25519";
      };
      gentian = lib.mkIf (config.my.is_private or false) {
        hostname = "zqnr.de";
        user = "vkarasen";
        # identityFile = "~/.ssh/id_ed25519";
        forwardAgent = true;
        forwardX11Trusted = true;
      };
    };
  };
}

