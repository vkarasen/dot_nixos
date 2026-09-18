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

    # Flip the battery "exception mode" flag that the root
    # battery-exception-watch timer (modules/nixos/laptop.nix) reads. Arming
    # only makes sense on AC (charging to full on battery is a no-op), so the
    # toggle refuses to arm when unplugged; disarming always works. The flag
    # lives in /run/user/1000 (tmpfs), so an exception never survives reboot.
    battery-exception-toggle = pkgs.writeShellApplication {
      name = "battery-exception-toggle";
      runtimeInputs = with pkgs; [libnotify]; # notify-send
      text = ''
        state=/run/user/1000/battery-exception
        mode=off
        if [ -r "$state" ]; then
          read -r mode < "$state" || true
        fi
        if [ "$mode" = "on" ]; then
          printf 'off\n' > "$state"
          notify-send -t 4000 "Battery exception OFF" "Back to 80% cap"
        else
          ac=""
          read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true
          if [ "$ac" = "1" ]; then
            printf 'on\n' > "$state"
            notify-send -t 4000 "Battery exception ON" "Charging to full (100/95) - reverts on unplug or Fn12"
          else
            notify-send -t 4000 "Battery exception" "Only works while plugged in (AC)"
          fi
        fi
      '';
    };

    # Waybar indicator: emit JSON with a class when the flag is armed, empty
    # text otherwise (waybar's hide-empty-text then hides the module).
    battery-exception-status = pkgs.writeShellScriptBin "battery-exception-status" ''
      state=/run/user/1000/battery-exception
      mode=off
      if [ -r "$state" ]; then
        read -r mode < "$state" || true
      fi
      if [ "$mode" = "on" ]; then
        printf '{"text":" ⚡","class":"exception","tooltip":"Battery exception: charging to full"}\n'
      else
        printf '{"text":""}\n'
      fi
    '';
  in {
    # NOTE: an aspect that defines a my.* option must never be consumed by a
    # standalone wrapped package (repo AGENTS.md pitfall #6) — this one isn't.
    config = {
      my.laptop.enable = true;

      # Battery exception mode (Fn12): toggle script + waybar status emitter.
      home.packages = [battery-exception-toggle battery-exception-status];

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
