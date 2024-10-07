{pkgs, ...}: {
  config = {
    home.packages = with pkgs; [
      openssh
    ];

    services.ssh-agent.enable = true;

    programs.ssh = {
      enable = true;
      addKeysToAgent = "yes";

      matchBlocks = {
        github = {
          hostname = "github.com";
          user = "git";
          identityFile = "~/.ssh/id_ed25519";
        };
        gentian = {
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
