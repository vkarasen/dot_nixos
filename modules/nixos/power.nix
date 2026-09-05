# Dendritic aspect: power management — lid/clamshell behaviour,
# suspend-then-hibernate, and conservative battery charging. Laptop-relevant;
# on a machine without the battery/lid hardware the units no-op gracefully.
{...}: {
  flake.modules.nixos.power = {...}: {
    # Clamshell mode: on AC, closing the lid does nothing (use with an
    # external monitor). On battery, suspend-then-hibernate: suspend now,
    # hibernate after HibernateDelaySec (15 min below).
    services.logind.lidSwitch = "suspend-then-hibernate";
    services.logind.lidSwitchExternalPower = "ignore";
    services.logind.lidSwitchDocked = "ignore";

    # How long to stay suspended before hibernating.
    systemd.sleep.settings.Sleep.HibernateDelaySec = "15min";

    # Conservative battery charging: charge to 85%, then let the battery
    # discharge to 70% before recharging. (Lenovo's "maximum lifespan" cap is
    # 80% if you want even more protection at the cost of capacity.) The EC
    # remembers these across reboots; this just re-applies them idempotently.
    systemd.services.battery-thresholds = {
      description = "Set conservative battery charge thresholds";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ -w /sys/class/power_supply/BAT0/charge_control_start_threshold ]; then
          echo 70 > /sys/class/power_supply/BAT0/charge_control_start_threshold
          echo 85 > /sys/class/power_supply/BAT0/charge_control_end_threshold
        fi
      '';
    };
  };
}
