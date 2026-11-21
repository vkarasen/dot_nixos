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
    config.flake.modules.nixos.solaar
    config.flake.modules.nixos.monitoring
    config.flake.modules.nixos.lock
    config.flake.modules.nixos.sleep
  ];

  # No laptop (wired desktop). Wifi via a USB dongle is optional — the wifi
  # aspect wires NetworkManager + the bishopNet profile — but ethernet is
  # primary. The Windows boot disk and the NTFS data disks (E:/F: — `G:` was
  # the SN730, now the persist disk) stay untouched and are mounted from
  # NixOS, not selected as aspects.
  flake.nixosHosts.sarasti.homeModules = [
    config.flake.modules.homeManager.core
    config.flake.modules.homeManager.desktop
    config.flake.modules.homeManager.firefox
    config.flake.modules.homeManager.steam
    config.flake.modules.homeManager.sarasti
  ];

  flake.modules.nixos.sarasti = {
    pkgs,
    lib,
    config,
    ...
  }: {
    networking.hostName = "sarasti";
    system.stateVersion = "26.05";

    # --- Guard: only NVMe by-id disks, and only two distinct ones ---
    # disko formats every disk named in `my.disks.*`. The Windows MBR boot disk
    # is a SATA disk 0 that must never be referenced here, so a typo'd
    # /dev/sdX path (or the same NVMe named twice) is caught at eval time
    # instead of at `nixos-anywhere` time, where it is unrecoverable.
    assertions = [
      {
        assertion = lib.hasPrefix "/dev/disk/by-id/nvme-" config.my.disks.mainDevice;
        message = "sarasti's disks must be distinct NVMe by-id paths; the Windows MBR disk must never be referenced.";
      }
      {
        assertion =
          config.my.disks.persistDevice
          != null
          && lib.hasPrefix "/dev/disk/by-id/nvme-" config.my.disks.persistDevice;
        message = "sarasti's disks must be distinct NVMe by-id paths; the Windows MBR disk must never be referenced.";
      }
      {
        assertion = config.my.disks.mainDevice != config.my.disks.persistDevice;
        message = "sarasti's disks must be distinct NVMe by-id paths; the Windows MBR disk must never be referenced.";
      }
    ];

    # --- Machine identity for the shared boot/disks aspects ---
    # Legacy BIOS/CSM for the dual-boot phase (Windows is legacy on its own
    # MBR disk); flip to "uefi" + Secure Boot once Windows is retired.
    my.boot.mode = "legacy";
    # Hibernation swapfile offset (resume_offset= kernel param). Measured
    # 2026-11-19 with `sudo btrfs inspect-internal map-swapfile -r
    # /swap/swapfile` against the current 64G swapfile; recompute if the
    # swapfile is recreated.
    my.boot.resumeOffset = 37586273;
    # VERIFY this by-id path at install time (ls -l /dev/disk/by-id/): the
    # 2 TB WD_BLACK SN770, NOT the 256 GB WD SN730 (the other NVMe).
    # Form is `nvme-<model>_<serial>` (the no-suffix link, not the `_1`
    # namespace twin and not model + EUI). Corrected 2026-10-26 from the
    # first live-ISO check; these strings are read off the live installer,
    # never assembled by hand.
    my.disks.mainDevice = "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_23426M405177";
    # Hibernation swapfile size. Bumped 32G -> 64G because zswap reserves
    # swap slots over days of uptime and the old 32G left too little headroom
    # for /sys/power/image_size (~12.5G on a 32G box). NOTE: this only takes
    # effect after a manual live recreate (disko won't touch an existing
    # swapfile) and REQUIRES recomputing my.boot.resumeOffset afterwards —
    # done 2026-11-19: the 64G swapfile was recreated live and resumeOffset
    # updated to the newly-measured 37586273 (see docs/hibernation.md).
    # The warnIf is a build-time gate: it fires if resumeOffset is ever set
    # back to the stale 32G value. The runtime counterpart is the
    # resume_offset check in the nixos.sleep wrapper, which REFUSES to
    # hibernate while live and configured offsets disagree.
    my.disks.swapSize =
      lib.warnIf
      (config.my.boot.resumeOffset == 533760)
      "sarasti: my.disks.swapSize=64G but my.boot.resumeOffset is still 533760 (the old 32G swapfile). Recreate the swapfile at 64G, recompute the offset (btrfs inspect-internal map-swapfile -r /swap/swapfile) and update resumeOffset BEFORE hibernating — see docs/hibernation.md."
      "64G";
    # Second persistent disk for /persist + /home, so reinstalling the SN770
    # leaves user data intact. VERIFY this by-id path at install time
    # (ls -l /dev/disk/by-id/): the 256 GB WD SN730, NOT the 2 TB SN770
    # targeted by mainDevice above.
    my.disks.persistDevice = "/dev/disk/by-id/nvme-WDC_PC_SN730_SDBQNTY-256G-1001_21022B801581";

    # --- GPU: AMD Radeon RX 6750 XT (RDNA2 / VCN 3.0) ---
    # VA-API decode is provided by mesa (radeonsi), which the shared
    # nixos.desktop aspect already installs via hardware.graphics.enable —
    # unlike troy (Intel iGPU), no extra driver package is needed. libva-utils
    # adds `vainfo` to verify hardware decode after install. RDNA2 has
    # hardware AV1 decode, so unlike troy we do NOT disable media.av1.
    # `ssh-to-age` is needed on the host itself for sops/age enrollment
    # (derive the host pubkey, and the home-manager age key, from
    # /persist/etc/ssh/ssh_host_ed25519_key) — see
    # docs/nixos-install.md §8 steps 0.5 and 6.
    environment.systemPackages = [pkgs.libva-utils pkgs.ssh-to-age];
    # Optional GPU monitoring after first boot: pkgs.radeontop / pkgs.nvtop.

    # --- Hardware scan (captured with nixos-generate-config --no-filesystems
    # on 2026-10-26) ---
    # Only the deltas versus the shared boot aspect are listed; these lists
    # merge with boot.nix rather than replacing it. Don't import a full
    # hardware-config: disko already declares filesystems/LUKS/swap, and a
    # full scan would clash.
    # `ahci`: SATA controller — the legacy-Windows MBR boot disk and the NTFS
    # data disks (E:/F:). `usbhid`: stage-1 USB keyboard for the LUKS
    # passphrase fallback; this is a desktop with no built-in keyboard.
    boot.initrd.availableKernelModules = ["ahci" "usbhid"];
    # Virtualisation host support (AMD-V).
    boot.kernelModules = ["kvm-amd"];
    # AMD microcode; base.nix enables redistributable firmware, so the
    # generate-config `mkDefault config.hardware.enableRedistributableFirmware`
    # guard is already satisfied by a plain `true`.
    hardware.cpu.amd.updateMicrocode = true;
  };

  # Host-specific *home* config. Empty for now: a desktop has no laptop Fn
  # keys, and RDNA2 has hardware AV1 decode so the Firefox default stays
  # (troy's Comet Lake iGPU needed media.av1.enabled=false). Kept as an
  # explicit aspect so future sarasti-only home bits have a home.
  flake.modules.homeManager.sarasti = {...}: {};
}
