# Dendritic aspect: declarative wifi (NetworkManager ensureProfiles) with the
# PSK sourced from sops. The SSID is not secret; only the PSK is. Shared across
# personal hosts (same home network); a host opts in via its modules list.
{...}: {
  flake.modules.nixos.wifi = {
    config,
    ...
  }: {
    networking.networkmanager.ensureProfiles = {
      profiles.home-wifi = {
        connection = {
          id = "home-wifi";
          type = "wifi";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "bishopNet";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
      # Map the sops secret straight onto the PSK setting (no env-var
      # interpolation needed). trim strips the trailing newline sops adds.
      secrets.entries = [
        {
          file = config.sops.secrets.wifi-home-psk.path;
          matchId = "home-wifi";
          # key is the bare property name — the agent prefixes the setting
          # name (802-11-wireless-security) itself, so this yields ...psk.
          key = "psk";
          trim = true;
        }
      ];
    };
  };
}
