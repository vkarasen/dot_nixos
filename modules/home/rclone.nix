# Dendritic aspect: rclone (home-manager class).
#
# Mounts Google Drive as a normal userspace path via rclone + FUSE.
# The mount is private-only; corporate configs should not enable it.
#
# Secret model:
#  • sops stores one full rclone.conf blob as `rclone_gdrive_conf`.
#  • The config is copied to ~/.config/rclone/rclone.conf on activation.
#  • A systemd user service mounts `gdrive:` at the canonical
#    `my.gdrive.mountPoint` and exposes it as `$GDRIVE_MOUNTPOINT`.
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
  flake.modules.homeManager.rclone = {
    lib,
    config,
    pkgs,
    ...
  }: let
    mountPoint = config.my.gdrive.mountPoint;
    rcloneConfigDir = "${config.home.homeDirectory}/.config/rclone";
    rcloneConfigFile = "${rcloneConfigDir}/rclone.conf";
    cacheDir = "${config.home.homeDirectory}/.cache/rclone";
    rcloneBin = "${config.home.homeDirectory}/.nix-profile/bin/rclone";
    # Resolved via the service PATH (see Environment below) so it works on
    # NixOS (/run/wrappers/bin) and non-NixOS (/bin or /usr/bin) alike.
    fusermountBin = "fusermount3";
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
  in
    lib.mkIf config.my.is_private {
      home.packages = [
        pkgs.rclone
      ];

      # Materialize the secret config file for rclone.
      home.activation.writeRcloneConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -Dm600 \
          "${config.sops.secrets.rclone_gdrive_conf.path}" \
          "${rcloneConfigFile}"
      '';

      # Expose the canonical mount path to shells and agent tooling.
      home.sessionVariables.GDRIVE_MOUNTPOINT = mountPoint;

      # This private profile uses Google Drive as the synced storage location
      # for the environment-global Obsidian vault.  Other environments can
      # override this option to point at local, SharePoint, Azure, or other
      # storage without changing the vault semantics.
      my.obsidian.globalVault.dir = lib.mkDefault "${mountPoint}/obsidian/${config.my.obsidian.globalVault.name}";

      # Only the cache dir is prepared at activation. The mountpoint itself is
      # created/removed by the systemd unit (ExecStartPre/ExecStopPost) so it
      # only ever exists while mounted — a write to it while unmounted fails
      # loudly (ENOENT) instead of silently landing on local disk.
      home.activation.prepareRcloneDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m700 "${cacheDir}"
      '';

      systemd.user.services.rclone-gdrive = {
        Unit = {
          Description = "Mount Google Drive with rclone";
          Wants = ["sops-nix.service"];
          After = ["sops-nix.service"];
        };

        Service = {
          Type = "simple";
          # PATH must let rclone's bash wrapper find a *setuid* fusermount3 before
          # its own bundled non-setuid store copy. On NixOS the setuid helper is
          # /run/wrappers/bin/fusermount3; on non-NixOS hosts it lives in /bin or
          # /usr/bin (e.g. Debian's /bin/fusermount3). /run/wrappers/bin stays
          # first for NixOS; /bin:/usr/bin cover non-NixOS without any sudo/reboot
          # state (the /run/wrappers symlink trick is tmpfs and does not persist).
          Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/bin:/usr/bin";
          # Tripwire: the mountpoint only exists while mounted. ExecStartPre
          # creates it (fusermount3 requires write access to the mountpoint);
          # ExecStopPost removes it again with `rmdir`, which only ever removes
          # an empty dir — so a write to ~/mnt/gdrive while unmounted fails
          # loudly (ENOENT), and any stray file that does appear makes the next
          # mount fail loudly ("is not empty") as a backstop. ExecStopPost runs
          # even when the mount fails to start, so the guard re-arms every cycle.
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p \"${mountPoint}\"";
          ExecStart = "${rcloneBin} ${commonMountArgs}";
          ExecStop = "${fusermountBin} -u ${mountPoint}";
          ExecStopPost = "${pkgs.coreutils}/bin/rmdir \"${mountPoint}\"";
          Restart = "on-failure";
          RestartSec = "5s";
        };

        Install = {
          WantedBy = ["default.target"];
        };
      };
    };
}
