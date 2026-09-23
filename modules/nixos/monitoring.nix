# Dendritic aspect: monitoring (nixos class) — system-level grants for the
# monitoring tools installed by the homeManager.monitoring aspect.
#
# btop reads GPU stats through the kernel perf subsystem. On Intel iGPUs that
# requires CAP_PERFMON; on NVIDIA/AMD btop uses NVML/ROCm instead, so this grant
# is a harmless no-op there. Keeping it generic means every host gets btop's GPU
# panel with no per-host wiring — a host opts in by listing this aspect in its
# `modules` list (see modules/hosts/troy.nix).
{...}: {
  flake.modules.nixos.monitoring = {pkgs, ...}: {
    security.wrappers.btop = {
      owner = "root";
      group = "root";
      capabilities = "cap_perfmon+ep";
      source = "${pkgs.btop}/bin/btop";
    };
  };
}
