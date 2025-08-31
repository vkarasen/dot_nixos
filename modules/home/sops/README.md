# Secrets Management with sops-nix

This configuration now uses [sops-nix](https://github.com/Mic92/sops-nix) for secure secrets management instead of the previous custom implementation.

## Why sops-nix?

sops-nix provides significant advantages over storing plain text secrets:

- ✅ **Encrypted at rest** - secrets are encrypted and safe to commit to git
- ✅ **Declarative configuration** - secrets defined in Nix configuration
- ✅ **Multiple encryption methods** - supports age, GPG, SSH keys
- ✅ **Team collaboration** - supports multiple keys and key rotation
- ✅ **Template support** - embed secrets in configuration files safely
- ✅ **Proper systemd integration** - uses systemd user services
- ✅ **Battle-tested** - used by nix-community infrastructure

## Setup Instructions

### 1. Generate an age key

```bash
# Create the age key directory
mkdir -p ~/.config/sops/age

# Generate a new age key
age-keygen -o ~/.config/sops/age/keys.txt

# Get your public key (you'll need this for .sops.yaml)
age-keygen -y ~/.config/sops/age/keys.txt
```

Alternatively, convert an existing SSH Ed25519 key:
```bash
mkdir -p ~/.config/sops/age
nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt"
```

### 2. Configure .sops.yaml

Edit `.sops.yaml` and replace the placeholder with your actual age public key:

```yaml
keys:
  - &user_key age1your_actual_public_key_here

creation_rules:
  - path_regex: secrets/[^/]+\.(yaml|json|env|ini)$
    key_groups:
    - age:
      - *user_key
```

### 3. Create your first secret file

```bash
# Install sops if not available
nix-shell -p sops

# Create and edit your secrets file (this will create a new encrypted file)
sops secrets.yaml
```

Add your secrets in YAML format:
```yaml
tavily_api_key: your_actual_api_key_here
openai_api_key: your_actual_openai_key_here
github_token: your_actual_github_token_here
```

When you save and exit, the file will be encrypted automatically.

**Important**: The file must not exist before running `sops`, or if it exists, it must already be a properly encrypted sops file. If you get a "sops metadata not found" error, delete the file and try again.

### 4. Configure secrets in your Nix configuration

Edit `modules/home/secrets.nix` and uncomment/configure the secrets you need:

```nix
{
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../secrets/example.yaml;

    # Define your secrets
    secrets.tavily_api_key = {};
    secrets.openai_api_key = {};
    secrets.github_token = {};
  };

  # Expose as environment variables
  home.sessionVariables = lib.mkMerge [
    (lib.mkIf (config.sops.secrets ? tavily_api_key) {
      TAVILY_API_KEY = "$(cat ${config.sops.secrets.tavily_api_key.path})";
    })
    (lib.mkIf (config.sops.secrets ? openai_api_key) {
      OPENAI_API_KEY = "$(cat ${config.sops.secrets.openai_api_key.path})";
    })
    (lib.mkIf (config.sops.secrets ? github_token) {
      GITHUB_TOKEN = "$(cat ${config.sops.secrets.github_token.path})";
    })
  ];
}
```

### 5. Apply the configuration

```bash
home-manager switch
```

The secrets will be decrypted by the `sops-nix.service` systemd user service and made available as environment variables in new shell sessions.

## Usage Examples

### Environment Variables
Secrets are automatically available as environment variables in new shells:
```bash
echo $TAVILY_API_KEY
echo $OPENAI_API_KEY
```

### Service Dependencies
If you have systemd user services that need secrets, make them depend on sops-nix:
```nix
systemd.user.services.myservice = {
  unitConfig.After = [ "sops-nix.service" ];
  # ... rest of service config
};
```

### Templates
You can embed secrets in configuration files using templates:
```nix
sops.templates."myapp-config.toml".content = ''
  api_key = "${config.sops.placeholder.tavily_api_key}"
  database_url = "postgres://user:${config.sops.placeholder.db_password}@localhost/mydb"
'';
```

## Managing Secrets

### Edit existing secrets
```bash
sops secrets/example.yaml
```

### Add new secrets
1. Edit the secrets file: `sops secrets/example.yaml`
2. Add the new secret to your Nix configuration
3. Run `home-manager switch`

### Add team members
1. Get their age public key
2. Add it to `.sops.yaml`
3. Update existing secrets: `sops updatekeys secrets/example.yaml`

### Rotate keys
```bash
# Update all secrets with new keys
sops updatekeys secrets/example.yaml
```

## Migration from Old System

If you were using the previous custom secrets system:

1. **Backup existing secrets**: Copy values from `~/.secrets/variables/`
2. **Remove old files**: `rm -rf ~/.secrets/`
3. **Setup sops-nix**: Follow the setup instructions above
4. **Add secrets to sops**: Use `sops secrets/example.yaml` to add your backed up values
5. **Update git ignore**: Remove `.secrets/` from `.gitignore` if it was there
6. **Clean up**: Remove the old activation script from your configuration

## Security Notes

- Age keys in `~/.config/sops/age/keys.txt` must be kept secure
- Encrypted `.sops` files are safe to commit to version control
- Secrets are decrypted to `$XDG_RUNTIME_DIR/secrets` (memory-backed on most systems)
- The `sops-nix.service` handles secure decryption at login time

## Troubleshooting

### Secrets not available
- Check that `sops-nix.service` is running: `systemctl --user status sops-nix`
- Verify age key exists: `ls -la ~/.config/sops/age/keys.txt`
- Check service logs: `journalctl --user -u sops-nix`

### Permission denied
- Ensure age key file has correct permissions: `chmod 600 ~/.config/sops/age/keys.txt`
- Check that the key directory is not world-readable

### Can't edit secrets
- Make sure `sops` is available: `nix-shell -p sops`
- Verify `.sops.yaml` is correctly configured
- Check that your age key can decrypt: `sops -d secrets/example.yaml`
