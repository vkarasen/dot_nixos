# Dendritic aspect: bootloader, swap, and the impermanence erase-on-boot
# rollback service.
{inputs, lib, ...}: {
  flake.modules.nixos.boot = {
    config,
    pkgs,
    ...
  }: {
    imports = [inputs.lanzaboote.nixosModules.lanzaboote];

    # Lanzaboote (Secure Boot): signs the boot chain and replaces the
    # systemd-boot install. Keys live in /persist so they survive the
    # erase-on-boot rollback.
    boot.lanzaboote = {
      enable = true;
      # Keep at most 10 generations on the ESP (each is a signed UKI + kernel
      # + initrd); older ones are pruned from the boot menu and the ESP.
      configurationLimit = 10;
      pkiBundle = "/persist/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys = {
        enable = true;
        # No surprise reboot: the user enters BIOS Setup Mode manually before
        # the enrollment boot.
        autoReboot = false;
        includeMicrosoftKeys = true;
      };
    };

    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = true;

    # systemd in stage-1: required for the rollback service and the TPM2
    # systemd-cryptenroll unlock. Default on nixos-unstable; kept explicit.
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

    # zram for day-to-day swap (fast, RAM-backed). The on-disk swapfile (see
    # modules/nixos/disks.nix) is the hibernation target via resume= +
    # resume_offset — hibernation ignores swap priority entirely; priority only
    # orders regular paging (zram first).
    zramSwap = {
      enable = true;
      memoryPercent = 100;
    };

    # Hibernate: resume from the LUKS-encrypted btrfs swapfile. resume_offset
    # is the physical location of /swap/swapfile on the btrfs device —
    # recompute with `btrfs inspect-internal map-swapfile -r /swap/swapfile`
    # if the swapfile is ever recreated (e.g. size change).
    boot.resumeDevice = "/dev/mapper/cryptroot";
    boot.kernelParams = ["resume_offset=533760"];

    # Erase-on-boot: roll the ephemeral root subvolume back to its blank
    # snapshot before sysroot mounts. First boot captures the pristine install
    # as the blank snapshot; subsequent boots wipe and restore.
    boot.initrd.systemd.services.rollback = {
      description = "Roll back root btrfs subvolume to pristine state";
      wantedBy = ["initrd.target"];
      after = [
        "systemd-cryptsetup@cryptroot.service"
        # A resume boot must NOT run the rollback (it would wipe the resumed
        # root) — order after hibernate-resume so a resume skips the wipe.
        "systemd-hibernate-resume@dev-mapper-cryptroot.service"
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

  };
}
