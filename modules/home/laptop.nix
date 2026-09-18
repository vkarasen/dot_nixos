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
# A "suspend exception" (Fn10, defined below) pauses this idle suspend while
# armed; it reverts on AC return or a second press of the key. The waybar
# module (custom/suspend-exception) shows a live countdown to the suspend,
# derived from a 1s idle listener so it shares hypridle's idle-inhibit
# awareness, and a moon while the exception is armed.
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
        # Skip the suspend when the "suspend exception" is armed (Fn10) — the
        # user has paused idle-suspend until AC returns or a second press.
        state=/run/user/1000/suspend-exception
        mode=off
        if [ -r "$state" ]; then
          read -r mode < "$state" || true
        fi
        if [ "$mode" != "on" ]; then
          /run/current-system/sw/bin/systemctl suspend-then-hibernate
        fi
      fi
    '';

    # Idle start/stop markers for the waybar countdown: a 1s hypridle listener
    # (below) calls these to record when the user went idle and clear it again
    # on activity. The timestamp file lives in /run/user/1000 (tmpfs).
    idle-mark = pkgs.writeShellScriptBin "idle-mark" ''
      ${pkgs.coreutils}/bin/date +%s > /run/user/1000/idle-suspend-since
    '';
    idle-clear = pkgs.writeShellScriptBin "idle-clear" ''
      ${pkgs.coreutils}/bin/rm -f /run/user/1000/idle-suspend-since
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

    # Flip the "suspend exception" flag (Fn10) that pauses the idle-suspend
    # listener while armed. Unlike the battery exception — which needs the root
    # battery-exception-watch timer to write EC thresholds — this is purely
    # user-space: the flag gates the idle-suspend script above, and the
    # suspend-exception-watch timer below disarms it when AC returns. The flag
    # lives in /run/user/1000 (tmpfs), so an exception never survives reboot.
    suspend-exception-toggle = pkgs.writeShellApplication {
      name = "suspend-exception-toggle";
      runtimeInputs = with pkgs; [libnotify]; # notify-send
      text = ''
        state=/run/user/1000/suspend-exception
        mode=off
        if [ -r "$state" ]; then
          read -r mode < "$state" || true
        fi
        if [ "$mode" = "on" ]; then
          printf 'off\n' > "$state"
          notify-send -t 4000 "Suspend exception OFF" "Idle suspend (5 min) re-enabled"
        else
          ac=""
          read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true
          if [ "$ac" = "0" ]; then
            printf 'on\n' > "$state"
            notify-send -t 4000 "Suspend exception ON" "Idle suspend paused - reverts on AC or Fn10"
          else
            notify-send -t 4000 "Suspend exception" "Only applies while on battery"
          fi
        fi
      '';
    };

    # Waybar indicator for the idle-suspend widget (custom/suspend-exception).
    # Always emits text so the bar layout stays put: a dim "-:--" placeholder
    # when nothing is counting, a moon while the exception is armed, and a
    # live countdown to the 5-min suspend while idle on battery.
    suspend-exception-status = pkgs.writeShellScriptBin "suspend-exception-status" ''
      state=/run/user/1000/suspend-exception
      mode=off
      if [ -r "$state" ]; then
        read -r mode < "$state" || true
      fi

      placeholder='{"text":" -:--","tooltip":"No suspend scheduled"}'

      # On AC the idle-suspend never fires.
      ac=""
      read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true
      if [ "$ac" != "0" ]; then
        printf '%s\n' "$placeholder"
        exit 0
      fi

      # Exception armed: idle-suspend is paused, show the moon instead.
      if [ "$mode" = "on" ]; then
        printf '{"text":" 🌙","class":"exception","tooltip":"Suspend exception: idle suspend paused"}\n'
        exit 0
      fi

      # Not idle yet: no countdown.
      idle_file=/run/user/1000/idle-suspend-since
      if [ ! -r "$idle_file" ]; then
        printf '%s\n' "$placeholder"
        exit 0
      fi

      since=""
      read -r since < "$idle_file" || true
      now=$(${pkgs.coreutils}/bin/date +%s)
      if [ -z "$since" ] || [ "$since" -ge "$now" ]; then
        printf '%s\n' "$placeholder"
        exit 0
      fi

      remaining=$((300 - (now - since)))
      if [ "$remaining" -le 0 ]; then
        printf '%s\n' "$placeholder"
        exit 0
      fi

      mm=$((remaining / 60))
      ss=$((remaining % 60))
      printf '{"text":" %d:%02d","class":"counting","tooltip":"Idle suspend in %d:%02d"}\n' "$mm" "$ss" "$mm" "$ss"
    '';

    # Polled by the suspend-exception-watch timer (below) to disarm the flag the
    # moment AC returns, keeping the waybar symbol honest even if the laptop
    # never idles while plugged in.
    suspend-exception-watch = pkgs.writeShellScriptBin "suspend-exception-watch" ''
      state=/run/user/1000/suspend-exception
      mode=off
      if [ -r "$state" ]; then
        read -r mode < "$state" || true
      fi
      if [ "$mode" = "on" ]; then
        ac=""
        read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true
        if [ "$ac" = "1" ]; then
          printf 'off\n' > "$state"
        fi
      fi
    '';
  in {
    # NOTE: an aspect that defines a my.* option must never be consumed by a
    # standalone wrapped package (repo AGENTS.md pitfall #6) — this one isn't.
    config = {
      my.laptop.enable = true;

      # Toggle + waybar status emitters for the two Fn-key exception modes:
      # battery (Fn12, charge-to-full) and suspend (Fn10, pause idle-suspend).
      home.packages = [
        battery-exception-toggle
        battery-exception-status
        suspend-exception-toggle
        suspend-exception-status
      ];

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
              # 1s idle: mark the idle start so the waybar widget can count down.
              # This listener shares hypridle's idle-inhibit awareness, so the
              # countdown pauses during video playback exactly like the real
              # suspend below does.
              timeout = 1;
              "on-timeout" = "${idle-mark}/bin/idle-mark";
              "on-resume" = "${idle-clear}/bin/idle-clear";
            }
            {
              timeout = 300; # 5 min idle
              "on-timeout" = "${idle-suspend}/bin/idle-suspend";
            }
          ];
        };
      };

      # Suspend exception (Fn10): a user-space timer polls the flag and disarms
      # it the moment AC returns ("deactivate on AC"). No root is involved — the
      # flag only gates the user-space idle-suspend script above — so this is a
      # user unit, unlike the root battery-exception-watch in
      # modules/nixos/laptop.nix (which must write EC thresholds).
      systemd.user.services.suspend-exception-watch = {
        Unit.Description = "Disarm the suspend exception when AC returns";
        Service = {
          Type = "oneshot";
          ExecStart = "${suspend-exception-watch}/bin/suspend-exception-watch";
        };
      };
      systemd.user.timers.suspend-exception-watch = {
        Unit.Description = "Poll for AC return to disarm the suspend exception";
        Timer = {
          OnBootSec = "30s";
          OnUnitActiveSec = "2s";
          AccuracySec = "1s";
        };
        Install.WantedBy = ["timers.target"];
      };
    };
  };
}
