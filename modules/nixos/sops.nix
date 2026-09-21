# Dendritic aspect: sops-nix (NixOS class) — system secrets + host age key.
# Shares the same encrypted secrets file as the home-manager aspect.
{
  inputs,
  config,
  ...
}: {
  flake.modules.nixos.sops = {lib, ...}: {
    imports = [inputs.sops-nix.nixosModules.sops];

    sops = {
      # Same encrypted file the home-manager aspect uses.
      defaultSopsFile = ../home/sops/secrets/secrets.yaml;

      # Host age key is derived from the SSH host key, persisted under /persist
      # via services.openssh.hostKeys (see modules/nixos/base.nix).
      age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

      # NixOS-level secrets get added here as needed.
      secrets = {
        # sha512crypt password hash for users.users.vkarasen. neededForUsers
        # makes sops decrypt it early so login works before the user session.
        user-password = {neededForUsers = true;};
      };
    };
  };
}
