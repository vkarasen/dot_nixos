# Dendritic aspect: use zqnr.de (a.k.a. "gentian") as a Nix remote build host.
# Confirmed via `ssh gentian` (2026-09-04): NixOS 26.11, 8 cores, 62 GiB RAM,
# KVM available, vkarasen in trusted-users, system-features =
# nixos-test benchmark big-parallel kvm.
{...}: {
  flake.modules.nixos.remote-builder = {...}: {
    nix = {
      distributedBuilds = true;

      buildMachines = [
        {
          hostName = "zqnr.de";
          # Both ends are nix 2.34.x -> the improved ssh-ng protocol is safe.
          protocol = "ssh-ng";
          sshUser = "vkarasen";
          # Verified passphrase-less, so the Nix daemon (running as root) can
          # authenticate non-interactively.
          sshKey = "/home/vkarasen/.ssh/id_ed25519";
          # Pinned host key: avoids TOFU and the daemon needing root's
          # known_hosts populated.
          publicHostKey = "AAAAC3NzaC1lZDI1NTE5AAAAINTF1LvQhChE3umF5ZO6VLwBm94NBkAnvvlac9OiR7mt";
          system = "x86_64-linux";
          maxJobs = 8; # 8 cores (nproc on gentian)
          supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"]; # gentian's system-features
        }
      ];

      settings.builders-use-substitutes = true;
    };
  };
}
