# Dendritic aspect: monitoring (home-manager class) — generic, vendor-neutral
# monitoring tooling, installed on every machine via core.nix.
#
# lm_sensors: the `sensors` CLI + libsensors for reading temperatures/fan speed
#       from hwmon (on ThinkPads thinkpad_acpi exposes fan1). Needs no privilege.
# btop: installed here ONLY on non-NixOS hosts (standalone home-manager /
#       headless). On NixOS, btop is provided by the system wrapper in
#       modules/nixos/monitoring.nix, which grants CAP_PERFMON so its GPU panel
#       works — so it is deliberately absent from home.packages there, to avoid
#       ~/.nix-profile/bin shadowing /run/wrappers/bin. A headless host has no
#       wrapper (and usually no sudo), so plain btop is the graceful fallback:
#       it keeps CPU/RAM/disk/net + sensors and only loses the GPU panel.
#       mission-center (the GUI dashboard) lives in modules/home/desktop.nix,
#       not here — it follows the GUI like every other desktop app.
#
# Vendor-specific monitoring (e.g. intel_gpu_top for an Intel iGPU) belongs in
# the host's own aspect (modules/hosts/<host>.nix), not here.
{...}: {
  flake.modules.homeManager.monitoring = {
    pkgs,
    config,
    lib,
    ...
  }: {
    home.packages = with pkgs;
      (lib.optionals (!config.my.is_nixos) [btop])
      ++ [lm_sensors];
  };
}
