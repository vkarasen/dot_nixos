{
  pkgs,
  config,
  lib,
  ...
}: {
  config = {
    home.packages = with pkgs; [
      openssh
    ];

    services.ssh-agent.enable = config.my.is_private;

    programs.ssh = {
      enable = true;
      addKeysToAgent =
        if config.my.is_private
        then "yes"
        else "no";

      matchBlocks = {
        github = {
          hostname = "github.com";
          user = "git";
          identityFile = "~/.ssh/id_ed25519";
        };
        gentian = lib.mkIf config.my.is_private {
          hostname = "zqnr.de";
          user = "vkarasen";
          identityFile = "~/.ssh/id_ed25519";
          forwardAgent = true;
          forwardX11Trusted = true;
        };
      };
    };
  };
}
