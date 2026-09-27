# Dendritic aspect: rclone (home-manager class).
#
# Declarative rclone targets via `my.rclone.mounts`:
#   type = "mount"   -> cached FUSE mount (systemd user service)
#   type = "sync"    -> one-way remote->local mirror (service + optional timer)
#   type = "bisync"  -> two-way sync with conflict handling (service + optional timer)
#
# Secrets: sops stores one full rclone.conf blob per remote
# (`rclone_gdrive_conf`, `rclone_nextcloud_conf`). They are concatenated into
# ~/.config/rclone/rclone.conf at activation, so every target shares one config.
#
# Auth flow (per remote, one time): `rclone config create <name> <backend> ...`
# (or `rclone config`), then save the resulting [<name>] section into sops as
# `rclone_<name>_conf`, rebuild. Every target referencing `<name>:` just works.
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
    cfg = config.my.rclone.mounts;
    rcloneBin = lib.getExe pkgs.rclone;
    fusermountBin = "fusermount3";
    rcloneConfigDir = "${config.xdg.configHome}/rclone";
    rcloneConfigFile = "${rcloneConfigDir}/rclone.conf";
    defaultCacheDir = "${config.xdg.cacheHome}/rclone";

    # Expand a leading ~/ (defensive; all canonical targets use absolute paths).
    expand = p:
      if lib.hasPrefix "~/" p
      then "${config.home.homeDirectory}/${lib.removePrefix "~/" p}"
      else p;

    # Shared mount flags. The two mounts diverge deliberately in two ways:
    #   * gdrive adds --poll-interval (Drive-only change polling, unsupported on
    #     WebDAV/Nextcloud) and therefore keeps --dir-cache-time 1000h — polling
    #     invalidates the directory cache on change, so a long TTL only saves
    #     redundant re-listings.
    #   * nextcloud (WebDAV, no polling) sets --dir-cache-time 1m so remote
    #     changes appear promptly the next time a directory is accessed.
    # Offline FILE access is unaffected by that: it comes from the VFS file
    # cache (--vfs-cache-mode full + --vfs-cache-max-age 720h below), not from
    # the directory-listing cache.
    commonMountArgs = [
      "--vfs-cache-mode"
      "full"
      "--vfs-cache-max-age"
      "720h"
      "--vfs-cache-max-size"
      "50G"
      "--vfs-cache-poll-interval"
      "5m"
      "--vfs-read-ahead"
      "128M"
      "--buffer-size"
      "16M"
      "--vfs-refresh"
      "--vfs-fast-fingerprint"
      "--umask"
      "077"
      "--file-perms"
      "0600"
      "--dir-perms"
      "0700"
    ];

    # Seed a bisync target on its first run: when the local dir has no files
    # yet, run with --resync (remote is authoritative) so bisync's empty-dir
    # safety check doesn't abort. Usage: rclone-bisync-seed <remote> <local> [rclone args...]
    bisyncSeed = pkgs.writeShellApplication {
      name = "rclone-bisync-seed";
      runtimeInputs = [pkgs.rclone pkgs.findutils];
      text = ''
        remote=$1
        local=$2
        shift 2
        if [ -z "$(find "$local" -type f -print -quit 2>/dev/null)" ]; then
          exec rclone bisync "$remote" "$local" --resync "$@"
        fi
        exec rclone bisync "$remote" "$local" "$@"
      '';
    };

    # Canonical local path of the environment-global Obsidian vault.
    vaultLocalDir =
      if config.my.obsidian.globalVault.dir == null
      then "${config.home.homeDirectory}/${config.my.obsidian.globalVault.name}"
      else config.my.obsidian.globalVault.dir;

    # Canonical target set. Hosts override individual fields by merging
    # (attrsOf submodule merges per-field). `enable` defaults to false, so
    # every live target sets it explicitly.
    targets = {
      gdrive = {
        enable = true;
        type = "mount";
        remote = "gdrive:";
        path = "/home/vkarasen/mnt/gdrive";
        extraArgs = commonMountArgs ++ ["--poll-interval" "1m" "--dir-cache-time" "1000h"];
      };
      nextcloud = {
        enable = true;
        type = "mount";
        remote = "nextcloud:";
        path = "/home/vkarasen/mnt/nextcloud";
        cacheDir = "${config.xdg.cacheHome}/rclone-nextcloud";
        extraArgs = commonMountArgs ++ ["--dir-cache-time" "1m"];
      };
      # Two-way offline copy of the Obsidian vault. The remote lives in gdrive;
      # the local path is governed by my.obsidian.globalVault.dir (vaultLocalDir).
      vault = {
        enable = true;
        type = "bisync";
        remote = "gdrive:obsidian/${config.my.obsidian.globalVault.name}";
        path = vaultLocalDir;
        interval = "*:0/15";
        extraArgs = ["--resilient" "--recover" "--max-lock" "2m"];
      };
      # Two-way offline copy of the Nextcloud private folder.
      private = {
        enable = true;
        type = "bisync";
        remote = "nextcloud:private";
        path = "${config.home.homeDirectory}/sync/private";
        interval = "*:0/15";
        extraArgs = ["--resilient" "--recover" "--max-lock" "2m"];
      };
    };

    # Per-target systemd unit builders.
    mkMount = name: t:
      lib.mkIf t.enable {
        "rclone-${name}" = {
          Unit = {
            Description = "Mount ${t.remote} at ${expand t.path} (rclone)";
            Wants = ["sops-nix.service"];
            After = ["sops-nix.service"];
          };
          Service = {
            Type = "simple";
            # PATH must let rclone's bash wrapper find a *setuid* fusermount3 before
            # its own bundled non-setuid store copy. On NixOS the setuid helper is
            # /run/wrappers/bin/fusermount3; on non-NixOS hosts it lives in /bin or
            # /usr/bin. /run/wrappers/bin stays first for NixOS; /bin:/usr/bin cover
            # non-NixOS without any sudo/reboot state.
            Environment = "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/bin:/usr/bin";
            # Tripwire: the mountpoint only exists while mounted. ExecStartPre
            # creates it; ExecStopPost removes it with `rmdir`, which only removes
            # an empty dir — a write to it while unmounted fails loudly (ENOENT).
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p \"${expand t.path}\"";
            ExecStart = "${rcloneBin} mount ${t.remote} \"${expand t.path}\" --config \"${rcloneConfigFile}\" --cache-dir \"${
              if t.cacheDir != null
              then expand t.cacheDir
              else defaultCacheDir
            }\" ${lib.concatStringsSep " " t.extraArgs}";
            ExecStop = "${fusermountBin} -u \"${expand t.path}\"";
            ExecStopPost = "${pkgs.coreutils}/bin/rmdir \"${expand t.path}\"";
            Restart = "on-failure";
            RestartSec = "5s";
          };
          Install.WantedBy = ["default.target"];
        };
      };

    mkSync = name: t:
      lib.mkIf t.enable {
        "rclone-${name}" = {
          Unit = {
            Description = "${t.type} ${t.remote} -> ${expand t.path} (rclone)";
            Wants = ["sops-nix.service"];
            After = ["sops-nix.service"];
          };
          Service = {
            Type = "oneshot";
            # Both bisync modes require the base dir to exist; rclone creates it
            # lazily for `sync` but bisync refuses to run otherwise.
            ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p \"${expand t.path}\"";
            # bisync refuses its first run against an empty local dir ("Empty
            # current PathN listing"), so the first run must seed with --resync.
            # Detect "first run" as "the local dir has no files yet" and append
            # --resync only then — no manual flag to add/remove, and an emptied
            # local dir re-seeds from the remote instead of erroring. The guard
            # lives in a writeShellApplication helper rather than an inline
            # nested $(...) in ExecStart: systemd runs ExecStart through
            # `/bin/sh -c`, where the inline form leaked a literal `)` into the
            # --resync argument (`unknown flag: --resync)`).
            ExecStart =
              if t.type == "bisync"
              then "${lib.getExe bisyncSeed} ${t.remote} \"${expand t.path}\" --config \"${rcloneConfigFile}\" ${lib.concatStringsSep " " t.extraArgs}"
              else "${rcloneBin} ${t.type} ${t.remote} \"${expand t.path}\" --config \"${rcloneConfigFile}\" ${lib.concatStringsSep " " t.extraArgs}";
          };
          Install.WantedBy = lib.optional (t.interval == null) "default.target";
        };
      };

    mkTimer = name: t:
      lib.mkIf (t.enable && t.interval != null) {
        "rclone-${name}" = {
          Unit.Description = "Timer for rclone ${t.type} ${name}";
          Timer = {
            OnCalendar = t.interval;
            Persistent = true;
          };
          Install.WantedBy = ["timers.target"];
        };
      };

    mountTargets = lib.filterAttrs (_: t: t.type == "mount") cfg;
    syncTargets = lib.filterAttrs (_: t: t.type != "mount") cfg;
    mountCacheDirs = lib.unique (map (t:
      if t.cacheDir != null
      then expand t.cacheDir
      else defaultCacheDir)
    (lib.filter (t: t.enable) (lib.attrValues mountTargets)));
  in
    lib.mkIf config.my.is_private {
      my.rclone.mounts = targets;

      home.packages = [pkgs.rclone];

      # Materialize the merged rclone.conf from the per-remote sops blobs.
      home.activation.writeRcloneConfig = lib.hm.dag.entryAfter ["writeBoundary" "sops-nix"] ''
        # sops-nix materializes secrets via its systemd user service, which
        # decrypts against the manifest of the generation systemd last
        # daemon-reloaded. Home-manager's own daemon-reload runs AFTER the
        # built-in sops-nix restart, so on the first switch that adds a new
        # secret that restart is a no-op and the secret file is absent. Force
        # a reload+restart here (linkGeneration has already relinked the unit)
        # so the secrets exist before we read them.
        if ${pkgs.systemd}/bin/systemctl --user is-system-running >/dev/null 2>&1; then
          $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user daemon-reload
          $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart sops-nix
        fi
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m700 "${rcloneConfigDir}"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m600 /dev/null "${rcloneConfigFile}"
        ${lib.optionalString (config.sops.secrets ? rclone_gdrive_conf) ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cat "${config.sops.secrets.rclone_gdrive_conf.path}" >> "${rcloneConfigFile}"
        ''}
        ${lib.optionalString (config.sops.secrets ? rclone_nextcloud_conf) ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/cat "${config.sops.secrets.rclone_nextcloud_conf.path}" >> "${rcloneConfigFile}"
        ''}
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 600 "${rcloneConfigFile}"
      '';

      # Only cache dirs are prepared at activation; mountpoints are created/
      # removed by each unit's ExecStartPre/ExecStopPost.
      home.activation.prepareRcloneDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${lib.concatMapStringsSep "\n" (d: "$DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m700 \"${d}\"") mountCacheDirs}
      '';

      # Trigger every sync/bisync target immediately after activation so a
      # switch syncs now instead of waiting for the next timer tick. `--no-block`
      # keeps a slow first seed from stalling activation (the unit runs detached).
      # daemon-reload first so the freshly-written units are known to systemd.
      home.activation.rcloneSyncNow = lib.hm.dag.entryAfter ["writeRcloneConfig"] ''
        $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user daemon-reload
        ${lib.concatMapStringsSep "\n" (name: "$DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user start --no-block rclone-${name}.service") (lib.attrNames (lib.filterAttrs (_: t: t.enable) syncTargets))}
      '';

      # Expose canonical mount paths to shells and agent tooling.
      home.sessionVariables = {
        GDRIVE_MOUNTPOINT = cfg.gdrive.path;
        NEXTCLOUD_MOUNTPOINT = cfg.nextcloud.path;
      };

      # The private profile's Obsidian vault lives locally at my.obsidian.
      # globalVault.dir; rclone bisyncs it against gdrive (see the `vault`
      # target above). The remote↔local mapping is owned here, not in obsidian.
      my.obsidian.globalVault.dir = lib.mkDefault "${config.home.homeDirectory}/sync/vault";

      systemd.user.services = lib.mkMerge (
        (lib.mapAttrsToList mkMount mountTargets) ++ (lib.mapAttrsToList mkSync syncTargets)
      );
      systemd.user.timers = lib.mkMerge (lib.mapAttrsToList mkTimer syncTargets);
    };
}
