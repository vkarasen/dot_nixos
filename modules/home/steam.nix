# Dendritic aspect: steam (home-manager class) — the user-space gaming overlay:
# MangoHud (Vulkan/GL HUD + FPS limiter). The system-side (Steam client, 32-bit
# drivers, controller udev rules) is modules/nixos/steam.nix.
{...}: {
  flake.modules.homeManager.steam = {...}: {
    programs.mangohud = {
      enable = true;
      # Cap at the panel refresh (60 Hz) — the single biggest battery/heat win
      # for 2D games, which otherwise render hundreds of fps. Settings apply
      # only while MangoHud is active: launch a game with `MANGOHUD=1
      # %command%` (or `mangohud %command%`) in Steam.
      settings = {
        fps_limit = 60;
      };
    };
  };
}
