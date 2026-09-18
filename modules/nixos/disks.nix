# Dendritic aspect: declarative partitioning via disko.
# GPT: 1 GiB ESP (vfat, /boot) + LUKS-encrypted btrfs pool with subvolumes.
# `root` is the ephemeral subvolume rolled back each boot (see boot.nix).
{inputs, ...}: {
  flake.modules.nixos.disks = {...}: {
    imports = [inputs.disko.nixosModules.disko];

    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          cryptroot = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              # Passphrase supplied by nixos-anywhere --disk-encryption-keys.
              passwordFile = "/tmp/secret.key";
              settings = {
                allowDiscards = true;
              };
              extraFormatArgs = ["--pbkdf" "argon2id"];
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "/log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  # Swapfile for hibernation; nodatacow/compress=none so btrfs
                  # leaves it alone. `btrfs filesystem mkswapfile` (used by
                  # disko) handles the rest.
                  "/swap" = {
                    mountpoint = "/swap";
                    mountOptions = ["nodatacow" "compress=none" "noatime"];
                    swap.swapfile.size = "32G";
                  };
                  # Steam library: a separate subvolume so games (re-downloadable
                  # runtime state) stay out of home snapshots/backups. The root
                  # of the subvolume is chowned at boot by a tmpfiles rule in
                  # modules/nixos/steam.nix. disko creates this subvolume on a
                  # fresh install; on an already-installed host it must be
                  # created once manually (btrfs subvolume create at the pool
                  # top level, mounted subvol=/).
                  "/games" = {
                    mountpoint = "/games";
                    # `nofail`: games are re-downloadable and non-boot-critical,
                    # so a missing subvolume must not block boot.
                    mountOptions = ["compress=zstd" "noatime" "nofail"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
