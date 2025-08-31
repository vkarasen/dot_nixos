# SOPS Configuration for Corporate Environment

This document explains how to use the sops secrets management in a corporate environment when importing the `homeManagerModules` from this flake.

## Overview

The sops module has been designed to work in both private and corporate environments:

- **Private environment** (`config.my.is_private = true`): Uses the predefined secrets and configuration from this flake
- **Corporate environment** (`config.my.is_private = false`): Provides basic sops facilities but allows custom configuration

## Setting Up Corporate Environment

### 1. Copy the Corporate SOPS Configuration

Copy `sops-corporate.yaml.example` to `.sops.yaml` in your corporate flake:

```bash
cp modules/home/sops/sops-corporate.yaml.example /path/to/your/corporate/flake/.sops.yaml
```

### 2. Generate Corporate Age Keys

```bash
# Generate a new age key for corporate use
age-keygen -o ~/.config/sops/age/keys.txt

# Get the public key
age-keygen -y ~/.config/sops/age/keys.txt
```

### 3. Update the Corporate SOPS Configuration

Edit your `.sops.yaml` file and replace the placeholder key with your actual corporate public key.

### 4. Configure Your Corporate Flake

In your corporate flake, configure the sops module:

```nix
{
  homeConfigurations.your-user = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;

    modules = homeManagerModules ++ [
      {
        # Set to corporate environment
        config.my.is_private = false;

        # Configure corporate secrets
        config.sops = {
          defaultSopsFile = ./secrets/corporate-secrets.yaml;

          # Define your corporate secrets
          secrets = {
            corporate_api_key = {};
            database_password = {};
            # Add other corporate secrets as needed
          };
        };

        # Set up corporate environment variables
        config.home.sessionVariables = {
          CORPORATE_API_KEY = "$(cat ${config.sops.secrets.corporate_api_key.path})";
          DB_PASSWORD = "$(cat ${config.sops.secrets.database_password.path})";
          # Add other environment variables as needed
        };
      }
    ];
  };
}
```

### 5. Create Corporate Secrets

Create and edit your corporate secrets file:

```bash
# Create the secrets directory
mkdir -p secrets

# Create and edit corporate secrets
sops secrets/corporate-secrets.yaml
```

## What's Available

### Always Available (Both Environments)

- Basic sops-nix functionality
- Age key management
- Secret decryption capabilities
- Custom secrets configuration

### Private Environment Only (`config.my.is_private = true`)

- Predefined `tavily_api_key` secret
- Automatic `TAVILY_API_KEY` environment variable
- Default secrets file from this flake
- Any other private-specific secrets added to this flake

### Corporate Environment (`config.my.is_private = false`)

- Clean slate for corporate secrets
- Custom `defaultSopsFile` configuration
- Custom secrets and environment variables
- No private secrets or environment variables

## Best Practices

1. **Separate Keys**: Use different age keys for private and corporate environments
2. **Separate Files**: Keep corporate secrets in separate files from private secrets
3. **Access Control**: Ensure corporate keys are only accessible to authorized personnel
4. **Documentation**: Document your corporate secrets and their purposes
5. **Rotation**: Regularly rotate corporate secrets and keys

## Troubleshooting

- Ensure your age key file exists at `~/.config/sops/age/keys.txt`
- Verify the public key in `.sops.yaml` matches your private key
- Check that the secrets file path in `defaultSopsFile` is correct
- Ensure proper file permissions on your age key file (600)
