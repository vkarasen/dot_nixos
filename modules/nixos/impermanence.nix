# Dendritic aspect: impermanence (erase-on-boot) + opt-in persistence.
{inputs, ...}: {
  flake.modules.nixos.impermanence = {lib, ...}: {
    imports = [inputs.impermanence.nixosModules.impermanence];

    # /persist and /var/log must be mounted early enough for boot services.
    fileSystems."/persist".neededForBoot = true;
    fileSystems."/var/log".neededForBoot = true;

    environment.persistence."/persist" = {
      directories = [
        # NixOS assigns UIDs/GIDs for declarative users/groups here; persisting
        # it keeps ownership stable across the erase-on-boot rollback (else
        # files in /home and /nix would be owned by reassigned ids).
        "/var/lib/nixos"
        # Bluetooth pairings (re-pairing devices each boot is annoying).
        "/var/lib/bluetooth"
        # Wifi profiles added at runtime (nmtui/nmcli/nm-applet) so ad-hoc
        # connections survive the erase-on-boot root.
        "/etc/NetworkManager/system-connections"
      ];
      files = [
        # Stable machine-id so journalctl can follow logs across reboots.
        "/etc/machine-id"
      ];
    };

    # An erased root makes sudo "lecture" on every boot; suppress it.
    security.sudo.extraConfig = ''
      Defaults lecture = never
    '';
  };
}
