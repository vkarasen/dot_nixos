# Dendritic aspect: host "troy" (ThinkPad T14s Gen 1, Intel Comet Lake).
# Declares itself as a NixOS host and lists the shared system aspects it uses.
{
  config,
  lib,
  ...
}: {
  flake.nixosHosts.troy.modules = [
    config.flake.modules.nixos.base
    config.flake.modules.nixos.boot
    config.flake.modules.nixos.disks
    config.flake.modules.nixos.impermanence
    config.flake.modules.nixos.sops
    config.flake.modules.nixos.remote-builder
    config.flake.modules.nixos.wifi
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.stylix
    config.flake.modules.nixos.lock
  ];

  # Home-manager aspects this host opts into. `core` is the universal tooling;
  # desktop/kanshi are the GUI (a laptop or a desktop PC alike); laptop is the
  # suspend/idle/battery behaviour specific to a laptop. browser follows
  # desktop: it is gated on my.gui.enable, so it only activates on GUI hosts.
  # `troy` (defined below) carries this host's own hardware-specific home bits.
  flake.nixosHosts.troy.homeModules = [
    config.flake.modules.homeManager.core
    config.flake.modules.homeManager.desktop
    config.flake.modules.homeManager.browser
    config.flake.modules.homeManager.kanshi
    config.flake.modules.homeManager.laptop
    config.flake.modules.homeManager.troy
  ];

  flake.modules.nixos.troy = {pkgs, ...}: {
    networking.hostName = "troy";

    system.stateVersion = "26.05";

    # Troy's iGPU is Intel UHD Graphics (Comet Lake, PCI 8086:9b41); the
    # Intel VA-API driver (iHD) enables Firefox hardware video decode, and
    # libva auto-detects iHD. Host-specific hardware belongs here rather than
    # in the shared nixos.desktop aspect, since other hosts using desktop
    # will not be Intel-graphics based.
    hardware.graphics.extraPackages = [pkgs.intel-media-driver];

    # Hardware scan (kernel modules, cpu governor, firmware) is captured after
    # first boot with `nixos-generate-config --no-filesystems` and folded in
    # here — see docs/nixos-install.md §5. Don't import a full hardware-config:
    # disko already declares filesystems/LUKS/swap, and a full scan would clash.
  };

  # Host-specific *home* config — the home-class counterpart of `nixos.troy`
  # above. It lives here, not in a shared aspect, because it is tied to this
  # machine's hardware: the ThinkPad top-row "Fn" keys report raw evdev codes
  # from the thinkpad-extra-buttons device, and a different laptop would differ.
  # See the "Host troy" section of the config-change skill for the keycode table.
  flake.modules.homeManager.troy = {
    pkgs,
    lib,
    ...
  }: let
    # Toggle DPMS on the internal panel only (eDP/LVDS), leaving any external
    # monitor untouched — works docked or undocked. Bound to Fn9 below.
    laptop-screen-toggle = pkgs.writeShellApplication {
      name = "laptop-screen-toggle";
      runtimeInputs = with pkgs; [hyprland jq];
      text = ''
        mon=$(hyprctl monitors -j | jq -r '[.[] | select(.name | test("^(eDP|LVDS)"))][0].name // empty')
        if [ -z "$mon" ]; then
          echo "laptop-screen-toggle: no internal (eDP/LVDS) monitor found" >&2
          exit 1
        fi
        expr="hl.dsp.dpms({ monitor = \"$mon\", action = \"toggle\" })"
        hyprctl dispatch "$expr"
      '';
    };
  in {
    config = {
      # The internal-panel DPMS toggle is usable as a command too.
      home.packages = [laptop-screen-toggle];

      # Fn9 = internal panel on/off. Hyprland `code:N` is the XKB keycode
      # (evdev + 8); Fn9 emits evdev 444 (KEY_NOTIFICATION_CENTER), so the bind
      # key is code:452.
      wayland.windowManager.hyprland.settings.bind = [
        {
          _args = [
            "code:452"
            (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("laptop-screen-toggle")'')
          ];
        }
        {
          # Fn12 (evdev 156 -> xkb 164) — battery exception toggle: charge to
          # full (100/95) for one stretch; reverts on unplug or a second press.
          _args = [
            "code:164"
            (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("battery-exception-toggle")'')
          ];
        }
      ];
    };
  };
}
