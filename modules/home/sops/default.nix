{
  lib,
  config,
  pkgs,
  ...
}: {
  config = {
    # Install sops binary for secrets management
    home.packages = [ pkgs.sops ];
    
    # Enable sops-nix for secrets management (always available)
    sops = {
      # Use age key from ~/.config/sops/age/keys.txt (default location)
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      # Conditional sops file based on environment
      defaultSopsFile = 
        if config.my.is_private 
        then ./secrets/secrets.yaml
        else null; # Corporate environment should set their own defaultSopsFile

      # Private secrets - only available when is_private is true
      secrets = lib.mkIf config.my.is_private {
        tavily_api_key = {
          # This will make the secret available as an environment variable
          # The secret will be decrypted to $XDG_RUNTIME_DIR/secrets/tavily_api_key
        };
        #
        # openai_api_key = {};
        #
        # github_token = {};
      };
    };

    # Set up environment variables from sops secrets
    # This requires the sops-nix home-manager module to be loaded
    home.sessionVariables = lib.mkMerge [
      # Private environment variables - only when is_private is true
      (lib.mkIf (config.my.is_private && config.sops.secrets ? tavily_api_key) {
        TAVILY_API_KEY = "$(cat ${config.sops.secrets.tavily_api_key.path})";
      })
      #
      # (lib.mkIf (config.my.is_private && config.sops.secrets ? openai_api_key) {
      #   OPENAI_API_KEY = "$(cat ${config.sops.secrets.openai_api_key.path})";
      # })
    ];
  };
}

