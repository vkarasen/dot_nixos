# Dendritic aspect: base NixOS system config (shared across personal hosts).
# Everything hardware- or host-specific lives in modules/hosts/<name>.nix.
{...}: {
  flake.modules.nixos.base = {
    config,
    pkgs,
    lib,
    ...
  }: {
    # Personal machine: enables the sops / rclone / pi private paths that gate
    # on my.is_private.
    my.is_private = true;

    # Intel wifi + misc firmware. Redistributable firmware is opt-in in this
    # nixpkgs (enableRedistributableFirmware defaults to enableAllFirmware =
    # false); without it the AX201 has no iwlwifi-QuZ ucode and no wifi device.
    hardware.enableRedistributableFirmware = true;

    nix.settings.experimental-features = ["nix-command" "flakes"];
    # Home setup: accept unsigned paths copied from the workstation / build
    # host over SSH (local builds and zqnr.de aren't signed by a key this
    # machine trusts). Proper hardening = signing keys + trusted-public-keys.
    nix.settings.require-sigs = false;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    networking.networkmanager.enable = true;

    time.timeZone = "Europe/Dublin";
    i18n.defaultLocale = "en_US.UTF-8";

    # CapsLock as Escape (muscle memory). Applies to the TTY console via XKB;
    # Hyprland will mirror this via its own kb_options when the desktop lands.
    console.useXkbConfig = true;
    services.xserver.xkb.options = "caps:escape";

    services.openssh = {
      enable = true;
      # Host keys live directly under /persist — NOT via a whole-/etc/ssh bind
      # mount, which hides the declarative sshd_config symlink and prevents
      # sshd from starting. grahamc's "erase your darlings" pattern.
      hostKeys = [
        {
          path = "/persist/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/persist/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
        }
      ];
      # Harden (PasswordAuthentication false, etc.) once the setup is proven.
    };

    users.users.vkarasen = {
      isNormalUser = true;
      description = "Vlad Karasen";
      extraGroups = ["wheel" "networkmanager"];
      # Keep the user systemd session alive from boot so home-manager's
      # user-level sops-nix.service can decrypt secrets before the system-level
      # home-manager activation needs them (rclone/workspace creds).
      linger = true;
      # Password login hash comes from sops (secrets.yaml) so no hash is
      # committed in plaintext. Don't use `passwd` to change it — that only
      # edits the ephemeral /etc/shadow and is lost on reboot.
      hashedPasswordFile = config.sops.secrets.user-password.path;
      # SSH key baked in so first boot is also reachable over SSH.
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOXgwQ23wvtnp8gkh6OUSP1I7SEfBMR4QYePWHhyl6eD vkarasen@gmail.com"
      ];
    };

    environment.systemPackages = with pkgs; [
      vim
      git
    ];
  };
}
