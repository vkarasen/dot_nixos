# Dendritic aspect: bootloader, swap, and the impermanence erase-on-boot
# rollback service.
{lib, ...}: {
  flake.modules.nixos.boot = {
    config,
    pkgs,
    ...
  }: {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    # systemd in stage-1: required for the rollback service (and the future
    # TPM2 systemd-cryptenroll unlock path). Default on nixos-unstable; kept
    # explicit for clarity.
    boot.initrd.systemd.enable = true;

    # Minimal modules to reach the LUKS+btrfs root on first boot. The full
    # hardware scan is captured post-boot via `nixos-generate-config
    # --no-filesystems` (docs/nixos-install.md §5) and folded in here.
    boot.initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "usb_storage"
      "sd_mod"
      "thunderbolt"
      # TPM2 (STM TPM over LPC/SPI on this ThinkPad) — needed in the initrd so
      # systemd-cryptsetup can auto-unlock the LUKS root via the TPM2 token.
      "tpm_tis"
    ];

    # zram for day-to-day swap (RAM-constrained laptop). The on-disk swapfile
    # (see modules/nixos/disks.nix) is reserved for hibernation.
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };

    # Erase-on-boot: roll the ephemeral root subvolume back to its blank
    # snapshot before sysroot mounts. First boot captures the pristine install
    # as the blank snapshot; subsequent boots wipe and restore.
    boot.initrd.systemd.services.rollback = {
      description = "Roll back root btrfs subvolume to pristine state";
      wantedBy = ["initrd.target"];
      after = [
        "systemd-cryptsetup@cryptroot.service"
        # When hibernation is enabled, additionally order after
        # "systemd-hibernate-resume@dev-mapper-cryptroot.service" so a resume
        # boot never runs the rollback (it would wipe the resumed root).
      ];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /mnt
        mount -o subvol=/ /dev/mapper/cryptroot /mnt
        if btrfs subvolume show /mnt/root-blank >/dev/null 2>&1; then
          # Defensive: delete any nested subvolumes under root before rolling
          # it back. No-op on the current flat layout (home/nix/persist/log/
          # swap/root-blank are top-level siblings), but keeps this safe if a
          # nested subvolume ever appears.
          btrfs subvolume list -o /mnt/root | cut -f9- -d' ' | while read -r subvolume; do
            echo "deleting nested subvolume /mnt/$subvolume"
            btrfs subvolume delete "/mnt/$subvolume"
          done
          echo "deleting root subvolume"
          btrfs subvolume delete /mnt/root
          echo "restoring root from blank snapshot"
          btrfs subvolume snapshot /mnt/root-blank /mnt/root
          # systemd's PrivateTmp mounts a tmpfs over /tmp and /var/tmp; that
          # fails (EPERM) when those dirs are COW-shared with the read-only
          # root-blank snapshot. Recreate them fresh to break the sharing.
          rm -rf /mnt/root/tmp /mnt/root/var/tmp
          mkdir -m 1777 /mnt/root/tmp /mnt/root/var/tmp
        else
          echo "first boot: capturing pristine root as blank snapshot"
          btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
        fi
        umount /mnt
      '';
    };

    # Hibernation (deferred until after first install):
    #   btrfs inspect-internal map-swapfile -r /swap/swapfile   # -> offset
    # then set:
    #   boot.resumeDevice = "/dev/mapper/cryptroot";
    #   boot.kernelParams = [ "resume_offset=<n>" ];
    # and enable suspend-then-hibernate via systemd.sleep.extraConfig
    # (HibernateDelaySec) + add the hibernate-resume unit to `after` above.
  };
}
