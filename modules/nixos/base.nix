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

    # Setuid fusermount3 so userspace FUSE mounts (the rclone gdrive mount)
    # work rootless. The home-manager rclone aspect resolves it via
    # /run/wrappers/bin (see modules/home/rclone.nix).
    security.wrappers.fusermount3 = {
      source = "${pkgs.fuse3}/bin/fusermount3";
      owner = "root";
      group = "root";
      setuid = true;
    };

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

    # Baseline hardware services (independent of any desktop environment).
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    # Thunderbolt authorization (bolt daemon) — required for Thunderbolt docks
    # and devices to be authorized (PCIe tunneling: dock USB hub, ethernet,
    # etc.). DisplayPort alt-mode video itself doesn't need it.
    services.hardware.bolt.enable = true;
    services.fwupd.enable = true; # firmware updates
    # thermald is deliberately NOT enabled: the ThinkPad EC + thinkpad_acpi
    # DYTC handle thermal management, and thermald's own platform check
    # declines to run here.
    services.upower.enable = true; # battery/power status

    # Sound: PipeWire + WirePlumber (headless-capable; the desktop consumes it
    # too).
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      wireplumber.enable = true;
      alsa.enable = true;
      pulse.enable = true;
      jack.enable = true;
    };

    # Nerd font for terminal nerd-symbol rendering.
    fonts.packages = [pkgs.nerd-fonts.noto];

    time.timeZone = "Europe/Dublin";
    i18n.defaultLocale = "en_US.UTF-8";

    # CapsLock as Escape (muscle memory). Applies to the TTY console via XKB;
    # Hyprland will mirror this via its own kb_options when the desktop lands.
    console.useXkbConfig = true;
    services.xserver.xkb.options = "caps:escape";

    # Catppuccin mocha 16-colour palette for the TTY virtual console. The VT
    # only supports 16 ANSI colours (not the 24-bit scheme), so this remaps
    # them to catppuccin mocha. Colour 0 is the *background* on the VT, so it
    # is base (#1e1e2e), not the light surface used for "black" text in a real
    # terminal. Full truecolor needs a terminal emulator.
    console.colors = [
      "1e1e2e" "f38ba8" "a6e3a1" "f9e2af"
      "89b4fa" "f5c2e7" "94e2d5" "bac2de"
      "585b70" "f38ba8" "a6e3a1" "f9e2af"
      "89b4fa" "f5c2e7" "94e2d5" "a6adc8"
    ];

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
      description = "vkarasen"; # greeters show the username, not a full name
      extraGroups = ["wheel" "networkmanager" "video" "input"];
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
      bolt # boltctl, for managing Thunderbolt device authorization
    ];
  };
}
