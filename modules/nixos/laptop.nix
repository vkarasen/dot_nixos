# Dendritic aspect: laptop power management (NixOS class) — the system side of
# suspend/hibernate: lid/clamshell behaviour (with a grace period before
# sleeping), suspend-then-hibernate, and conservative battery charging. The
# user-space idle listeners live in modules/home/laptop.nix. Imported only by
# the laptop host (modules/hosts/troy.nix); without the battery/lid hardware
# the units no-op gracefully.
{...}: {
  flake.modules.nixos.laptop = {...}: {
    # The lid is handled by the lid-grace-watch timer below (delayed suspend),
    # so logind must not act on it. NOTE: logind.conf changes need a
    # `systemctl reload systemd-logind` (the switch activation does not do it).
    services.logind.settings.Login.HandleLidSwitch = "ignore";
    services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
    services.logind.settings.Login.HandleLidSwitchDocked = "ignore";

    # How long to stay suspended before hibernating.
    systemd.sleep.settings.Sleep.HibernateDelaySec = "15min";

    # Grace period: poll the lid state (via /proc/acpi/button/lid, which logind
    # does NOT grab — acpid is unusable here because logind holds the lid input
    # device) every 30s. On battery + lid closed, schedule suspend-then-
    # hibernate in 5 minutes (time to relocate without killing jobs/SSH); on
    # lid open, cancel it. On AC the lid does nothing (clamshell mode).
    systemd.timers.lid-grace-watch = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
      };
    };
    systemd.services.lid-grace-watch = {
      description = "Schedule a delayed suspend when the lid closes on battery";
      serviceConfig.Type = "oneshot";
      script = ''
        lid=""
        read lid < /proc/acpi/button/lid/LID/state 2>/dev/null || true
        ac=""
        read ac < /sys/class/power_supply/AC/online 2>/dev/null || true
        case "$lid" in
          *closed*)
            if [ "$ac" = "0" ]; then
              # on battery + lid closed: ensure the grace timer is scheduled
              if ! /run/current-system/sw/bin/systemctl is-active -q lid-grace-suspend.timer 2>/dev/null; then
                /run/current-system/sw/bin/systemd-run --on-active=5min \
                  --unit=lid-grace-suspend --quiet \
                  /run/current-system/sw/bin/systemctl suspend-then-hibernate
              fi
            else
              # plugged back in (clamshell): cancel any pending grace
              /run/current-system/sw/bin/systemctl stop lid-grace-suspend.timer 2>/dev/null || true
            fi
            ;;
          *)
            # lid open: cancel any pending grace
            /run/current-system/sw/bin/systemctl stop lid-grace-suspend.timer 2>/dev/null || true
            ;;
        esac
      '';
    };

    # Conservative battery charging (Lenovo's "maximum lifespan" profile):
    # charge to 80%, then let the battery discharge to 75% before recharging.
    # The EC remembers these across reboots; this just re-applies idempotently.
    systemd.services.battery-thresholds = {
      description = "Set conservative battery charge thresholds";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ -w /sys/class/power_supply/BAT0/charge_control_start_threshold ]; then
          echo 75 > /sys/class/power_supply/BAT0/charge_control_start_threshold
          echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold
        fi
      '';
    };

    # Exception mode (the "charge to full just this once" button, Fn12 — bound
    # in modules/hosts/troy.nix). The user toggle can only write a flag into
    # the user runtime dir (/run/user/1000/battery-exception, tmpfs -> never
    # survives reboot); the EC thresholds are root-only, so this timer polls
    # the flag and applies the thresholds. It also reverts to the conservative
    # default on AC disconnect (disarming the flag), giving one-shot
    # "charge cycle" semantics like the phone-style battery-saver override.
    systemd.timers.battery-exception-watch = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "2s";
        AccuracySec = "1s";
      };
    };
    systemd.services.battery-exception-watch = {
      description = "Apply battery thresholds from the exception-mode flag";
      serviceConfig.Type = "oneshot";
      script = ''
        state=/run/user/1000/battery-exception
        mode=off
        if [ -r "$state" ]; then
          read -r mode < "$state" || true
        fi

        ac=""
        read -r ac < /sys/class/power_supply/AC/online 2>/dev/null || true

        start=75
        end=80
        if [ "$mode" = "on" ]; then
          if [ "$ac" = "1" ]; then
            start=95
            end=100
          else
            # Unplugged while the exception was armed: disarm and fall back to
            # the conservative thresholds.
            printf 'off\n' > "$state"
          fi
        fi

        cur_start=""
        read -r cur_start < /sys/class/power_supply/BAT0/charge_control_start_threshold 2>/dev/null || true
        cur_end=""
        read -r cur_end < /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null || true
        if [ "$cur_start" != "$start" ] || [ "$cur_end" != "$end" ]; then
          if [ -w /sys/class/power_supply/BAT0/charge_control_start_threshold ]; then
            # The EC rejects any intermediate state where start >= end, so the
            # write order must preserve start < end at every step: raising ->
            # end first, lowering -> start first.
            if [ "$start" -gt "$cur_start" ]; then
              echo "$end" > /sys/class/power_supply/BAT0/charge_control_end_threshold
              echo "$start" > /sys/class/power_supply/BAT0/charge_control_start_threshold
            else
              echo "$start" > /sys/class/power_supply/BAT0/charge_control_start_threshold
              echo "$end" > /sys/class/power_supply/BAT0/charge_control_end_threshold
            fi
          fi
        fi
      '';
    };
  };
}
