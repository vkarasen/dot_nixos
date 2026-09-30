# Dendritic aspect: declarative wifi (NetworkManager ensureProfiles) with the
# PSK sourced from sops. The SSID is not secret; only the PSK is. Shared across
# personal hosts (same home network); a host opts in via its modules list.
{...}: {
  flake.modules.nixos.wifi = {config, ...}: {
    # The PSK is the only secret this aspect consumes — declare it here (not
    # in nixos/sops.nix) so it decrypts only on hosts that opt into wifi.
    sops.secrets.wifi-home-psk = {};

    # Render the PSK into an environment file (root-only, under /run — tmpfs,
    # never the nix store) so envsubst can substitute it into the profile at
    # activation time. Putting the PSK *in* the profile makes it system-owned,
    # so NM logs "system settings secrets sufficient" and never consults a
    # secret agent — no agent-order race on hibernate-resume.
    sops.templates."wifi-home-psk-env".content = ''
      WIFI_HOME_PSK=${config.sops.placeholder."wifi-home-psk"}
    '';

    networking.networkmanager.ensureProfiles = {
      # Loaded by NetworkManager-ensure-profiles.service (EnvironmentFile=) and
      # expanded by envsubst into the profile below. Only the placeholder
      # travels through the store; the plaintext lands in
      # /run/secrets/rendered/wifi-home-psk-env (0400 root).
      environmentFiles = [config.sops.templates."wifi-home-psk-env".path];

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
          # Literal $VAR — envsubst replaces it with the value from the
          # environment file when the profile is written to
          # /run/NetworkManager/system-connections/home-wifi.nmconnection.
          psk = "$WIFI_HOME_PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };
}
