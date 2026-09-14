# Dendritic aspect: core (home-manager class) — the universal baseline, folded
# into every configuration that wants the standard tooling (CLI editors, shell,
# git, ssh, pi + its MCP servers, obsidian, rclone/sops, …). Not a capability in
# its own right: it just imports the aspects wanted on every machine, so a host
# (or the standalone portable config) lists `core` once instead of ~23 aspects.
#
# Machine-specific capabilities (desktop, kanshi, laptop) are NOT here — those
# are selected explicitly per host. Adding a new always-on home aspect = add it
# to the imports below: one edit, no per-host list to touch.
{config, ...}: {
  flake.modules.homeManager.core = {
    imports = [
      config.flake.modules.homeManager.base
      config.flake.modules.homeManager.bash
      config.flake.modules.homeManager.git
      config.flake.modules.homeManager.ssh
      config.flake.modules.homeManager.external
      config.flake.modules.homeManager.shellPackages
      config.flake.modules.homeManager.television
      config.flake.modules.homeManager.tickrs
      config.flake.modules.homeManager.worktrunk
      config.flake.modules.homeManager.tmux
      config.flake.modules.homeManager.lf
      config.flake.modules.homeManager.neovim
      config.flake.modules.homeManager.obsidian
      config.flake.modules.homeManager.rclone
      config.flake.modules.homeManager.sops
      config.flake.modules.homeManager.pi
      config.flake.modules.homeManager.pi-agents
      config.flake.modules.homeManager.pi-mcp
      config.flake.modules.homeManager.pi-policies
      config.flake.modules.homeManager.pi-private
      config.flake.modules.homeManager.google-workspace
      config.flake.modules.homeManager.video-analyzer
      config.flake.modules.homeManager.herdr
    ];
  };
}
