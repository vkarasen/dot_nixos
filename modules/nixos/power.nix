# Dendritic aspect: power management — lid/clamshell behaviour (with a grace
# period before sleeping), suspend-then-hibernate, and conservative battery
# charging. Laptop-relevant; on a machine without the battery/lid hardware the
# units no-op gracefully.
{...}: {
  flake.modules.nixos.power = {...}: {
    # The lid is handled by the acpid handler below (delayed suspend), so
    # logind must not act on it directly.
    services.logind.lidSwitch = "ignore";
    services.logind.lidSwitchExternalPower = "ignore";
    services.logind.lidSwitchDocked = "ignore";

    # How long to stay suspended before hibernating.
    systemd.sleep.settings.Sleep.HibernateDelaySec = "15min";

    # Clamshell + grace period: closing the lid on battery schedules
    # suspend-then-hibernate in 5 minutes (time to relocate without killing
    # jobs/SSH); reopening cancels it. On AC the lid does nothing (clamshell
    # mode for an external monitor).
    services.acpid = {
      enable = true;
      lidEventCommands = ''
        case "$3" in
          close)
            /run/current-system/sw/bin/systemctl stop lid-grace-suspend.timer 2>/dev/null || true
            ac=1
            read ac < /sys/class/power_supply/AC/online 2>/dev/null || true
            if [ "$ac" = "0" ]; then
              /run/current-system/sw/bin/systemd-run --on-active=5min \
                --unit=lid-grace-suspend --quiet \
                /run/current-system/sw/bin/systemctl suspend-then-hibernate
            fi
            ;;
          open)
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
  };
}
