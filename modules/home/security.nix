# Security: SSH and sops secrets management
# Exports: flake.homeModules.security
{ ... }: {
  flake.homeModules.security = { pkgs, config, lib, ... }: {
    home.packages = with pkgs; [
      openssh
      sops
    ];

    # --- SSH ---
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
        };
        gentian = lib.mkIf (config.my.is_private or false) {
          hostname = "zqnr.de";
          user = "vkarasen";
          forwardAgent = true;
          forwardX11Trusted = true;
        };
      };
    };

    # --- sops-nix ---
    sops = {
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      defaultSopsFile =
        if config.my.is_private or false
        then ../../secrets/secrets.yaml
        else null;

      secrets = lib.mkIf (config.my.is_private or false) {
        tavily_api_key = {};
      };
    };

    home.sessionVariables = lib.mkMerge [
      (lib.mkIf ((config.my.is_private or false) && (config.sops.secrets ? tavily_api_key)) {
        TAVILY_API_KEY = "$(cat ${config.sops.secrets.tavily_api_key.path})";
      })
    ];
  };
}

