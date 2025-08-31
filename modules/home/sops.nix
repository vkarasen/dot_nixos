{
  lib,
  config,
  ...
}: {
  config = {
    # Enable sops-nix for secrets management
    sops = {
      # Use age key from ~/.config/sops/age/keys.txt (default location)
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

      # Default sops file - you can create this with: sops secrets.yaml
      defaultSopsFile = ../../secrets/secrets.yaml;

      # Example secrets - uncomment and configure as needed:
      secrets.tavily_api_key = {
        # This will make the secret available as an environment variable
        # The secret will be decrypted to $XDG_RUNTIME_DIR/secrets/tavily_api_key
      };
      #
      # secrets.openai_api_key = {};
      #
      # secrets.github_token = {};
    };

    # Set up environment variables from sops secrets
    # This requires the sops-nix home-manager module to be loaded
    home.sessionVariables = lib.mkMerge [
      # Example of how to expose secrets as environment variables:
      (lib.mkIf (config.sops.secrets ? tavily_api_key) {
        TAVILY_API_KEY = "$(cat ${config.sops.secrets.tavily_api_key.path})";
      })
      #
      # (lib.mkIf (config.sops.secrets ? openai_api_key) {
      #   OPENAI_API_KEY = "$(cat ${config.sops.secrets.openai_api_key.path})";
      # })
    ];
  };
}
