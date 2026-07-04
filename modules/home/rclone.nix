# Dendritic aspect: rclone (home-manager class).
#
# Mounts Google Drive as a normal userspace path via rclone + FUSE.
# The mount is private-only; corporate configs should not enable it.
#
# Secret model:
#  • sops stores one full rclone.conf blob as `rclone_gdrive_conf`.
#  • The config is copied to ~/.config/rclone/rclone.conf on activation.
#  • A systemd user service mounts `gdrive:` at ~/mnt/gdrive.
#
# Auth flow:
#  1. Create/choose a Google OAuth client for rclone.
#  2. Run `rclone config` once and complete the browser auth.
#  3. Save the resulting rclone.conf contents into sops.
#  4. Rebuild; the service will use the decrypted config on every machine.
#
# See also: modules/home/pi/skills/userspace-mounts/SKILL.md for the
# host-side fusermount/FUSE checklist and WSL guidance.

{...}: {
  flake.modules.homeManager.rclone = { lib, config, pkgs, ... }: let
    mountPoint = "${config.home.homeDirectory}/mnt/gdrive";
    rcloneConfigDir = "${config.home.homeDirectory}/.config/rclone";
    rcloneConfigFile = "${rcloneConfigDir}/rclone.conf";
    cacheDir = "${config.home.homeDirectory}/.cache/rclone";
    rcloneBin = "${config.home.homeDirectory}/.nix-profile/bin/rclone";
    fusermountBin = "/run/wrappers/bin/fusermount3";
    commonMountArgs = ''
      mount gdrive: "${mountPoint}" \
        --config "${rcloneConfigFile}" \
        --cache-dir "${cacheDir}" \
        --vfs-cache-mode writes \
        --dir-cache-time 1m \
        --poll-interval 1m \
        --umask 077 \
        --file-perms 0600 \
        --dir-perms 0700
    '';
  in lib.mkIf config.my.is_private {
    home.packages = [
      pkgs.rclone
    ];

    # Materialize the secret config file for rclone.
    home.activation.writeRcloneConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm600 \
        "${config.sops.secrets.rclone_gdrive_conf.path}" \
        "${rcloneConfigFile}"
    '';

    # Ensure the mount/cache directories exist before systemd starts the unit.
    home.activation.prepareRcloneDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m700 \
        "${mountPoint}" \
        "${cacheDir}"
    '';

    systemd.user.services.rclone-gdrive = {
      Unit = {
        Description = "Mount Google Drive with rclone";
        Wants = ["sops-nix.service"];
        After = ["sops-nix.service"];
      };

      Service = {
        Type = "simple";
        ExecStart = "${rcloneBin} ${commonMountArgs}";
        ExecStop = "${fusermountBin} -u ${mountPoint}";
        Restart = "on-failure";
        RestartSec = "5s";
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
