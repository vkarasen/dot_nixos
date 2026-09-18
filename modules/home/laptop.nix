# Dendritic aspect: laptop-specific behaviour (home-manager class) — the user-space
# side of suspend/hibernate. The system side (lid handling, the
# suspend-then-hibernate delay, battery thresholds) is modules/nixos/laptop.nix.
#
# Importing this aspect IS the laptop statement: it sets my.laptop.enable = true
# (the derived flag other aspects read for fine-grained laptop conditionals, e.g.
# the waybar battery module in modules/home/desktop.nix) and enables hypridle,
# whose listener implements the idle policy: on battery, 5 min idle ->
# suspend-then-hibernate (mirrors the lid-close grace in modules/nixos/laptop.nix).
# hypridle honours the Wayland idle-inhibit lock by default, so browsers/players
# that hold it during playback pause the timer. Locking happens only via
# before_sleep_cmd right before suspend — there is no idle auto-lock.
#
# Generic laptop-only Hyprland binds may live here (NOT in the PC-shared
# modules/home/desktop.nix — `settings.bind` is a merged list, so binds from
# this aspect concatenate with desktop.nix's). Host- or hardware-specific binds
# (e.g. troy's ThinkPad Fn keys) do NOT: they belong in the host's own aspect,
# `flake.modules.homeManager.<host>` (see modules/hosts/troy.nix).
{...}: {
  flake.modules.homeManager.laptop = {pkgs, ...}: let
    # Suspend on battery after idle. `read` is a shell builtin, so the script
    # needs nothing but bash plus the full-path systemctl below; a missing AC
    # node leaves `ac` empty -> no suspend (safe default).
    idle-suspend = pkgs.writeShellScriptBin "idle-suspend" ''
      ac=""
      read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true
      if [ "$ac" = "0" ]; then
        /run/current-system/sw/bin/systemctl suspend-then-hibernate
      fi
    '';
  in {
    # NOTE: an aspect that defines a my.* option must never be consumed by a
    # standalone wrapped package (repo AGENTS.md pitfall #6) — this one isn't.
    config = {
      my.laptop.enable = true;

      # Idle daemon: suspend on battery and lock right before suspend. See the
      # header comment for the policy.
      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "hyprlock";
            before_sleep_cmd = "hyprlock";
          };
          listener = [
            {
              timeout = 300; # 5 min idle
              "on-timeout" = "${idle-suspend}/bin/idle-suspend";
            }
          ];
        };
      };
    };
  };
}
