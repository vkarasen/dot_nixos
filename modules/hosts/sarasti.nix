# Dendritic aspect: host "sarasti" (MSI B550-A PRO desktop — AMD Ryzen 5 3600,
# Radeon RX 6750 XT, 32 GiB, all-SSD). Declares itself as a NixOS host and
# lists the shared system aspects it uses.
#
# Migration history: this was the "bishop-PC" Windows 10 desktop. It dual-boots
# Windows (legacy BIOS on a separate MBR disk, untouched) until Windows is
# retired, then flips my.boot.mode to "uefi" + Secure Boot — see
# docs/boot-modes.md and docs/nixos-install.md.
{config, ...}: {
  flake.nixosHosts.sarasti.modules = [
    config.flake.modules.nixos.base
    config.flake.modules.nixos.boot
    config.flake.modules.nixos.disks
    config.flake.modules.nixos.impermanence
    config.flake.modules.nixos.sops
    config.flake.modules.nixos.remote-builder
    config.flake.modules.nixos.wifi
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.gnome-keyring
    config.flake.modules.nixos.steam
    config.flake.modules.nixos.monitoring
    config.flake.modules.nixos.lock
  ];

  # No laptop (wired desktop). Wifi via a USB dongle is optional — the wifi
  # aspect wires NetworkManager + the bishopNet profile — but ethernet is
  # primary. The Windows boot disk and the NTFS data disks (E:/F:/G:) stay
  # untouched and are mounted from NixOS, not selected as aspects.
  flake.nixosHosts.sarasti.homeModules = [
    config.flake.modules.homeManager.core
    config.flake.modules.homeManager.desktop
    config.flake.modules.homeManager.firefox
    config.flake.modules.homeManager.steam
    config.flake.modules.homeManager.sarasti
  ];

  flake.modules.nixos.sarasti = {pkgs, ...}: {
    networking.hostName = "sarasti";
    system.stateVersion = "26.05";

    # --- Machine identity for the shared boot/disks aspects ---
    # Legacy BIOS/CSM for the dual-boot phase (Windows is legacy on its own
    # MBR disk); flip to "uefi" + Secure Boot once Windows is retired.
    my.boot.mode = "legacy";
    # Hibernation swapfile offset: set after first install with
    # `btrfs inspect-internal map-swapfile -r /swap/swapfile`
    # (my.boot.resumeOffset stays null until then).
    # VERIFY this by-id path at install time (ls -l /dev/disk/by-id/): the
    # 2 TB WD_BLACK SN770, NOT the 256 GB WD SN730 (the other NVMe).
    my.disks.mainDevice = "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_E823_8FA6_BF53_0001_001B_444A_414D_7FB8";
    # Second persistent disk for /persist + /home, so reinstalling the SN770
    # leaves user data intact. VERIFY this by-id path at install time
    # (ls -l /dev/disk/by-id/): the 256 GB WD SN730, NOT the 2 TB SN770
    # targeted by mainDevice above.
    my.disks.persistDevice = "/dev/disk/by-id/nvme-WDC_PC_SN730_SDBQNTY-256G-1001_001B_448B_4886_AE3B";

    # --- GPU: AMD Radeon RX 6750 XT (RDNA2 / VCN 3.0) ---
    # VA-API decode is provided by mesa (radeonsi), which the shared
    # nixos.desktop aspect already installs via hardware.graphics.enable —
    # unlike troy (Intel iGPU), no extra driver package is needed. libva-utils
    # adds `vainfo` to verify hardware decode after install. RDNA2 has
    # hardware AV1 decode, so unlike troy we do NOT disable media.av1.
    environment.systemPackages = [pkgs.libva-utils];
    # Optional GPU monitoring after first boot: pkgs.radeontop / pkgs.nvtop.

    # Hardware scan (kernel modules, cpu governor, firmware) is captured after
    # first boot with `nixos-generate-config --no-filesystems` and folded in
    # here — see docs/nixos-install.md. Don't import a full hardware-config:
    # disko already declares filesystems/LUKS/swap, and a full scan would clash.
  };

  # Host-specific *home* config. Empty for now: a desktop has no laptop Fn
  # keys, and RDNA2 has hardware AV1 decode so the Firefox default stays
  # (troy's Comet Lake iGPU needed media.av1.enabled=false). Kept as an
  # explicit aspect so future sarasti-only home bits have a home.
  flake.modules.homeManager.sarasti = {...}: {};
}
