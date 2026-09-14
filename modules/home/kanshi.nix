# Dendritic aspect: kanshi (home-manager class) — monitor profile manager,
# the "memory effect" for multiscreen. Known combos are declarative here;
# transient/unknown monitors go in a writable runtime include file so they
# survive reboots without polluting the flake.
{...}: {
  flake.modules.homeManager.kanshi = {
    pkgs,
    lib,
    config,
    ...
  }: {
    config = {
      home.packages = [
        pkgs.nwg-displays # the arandr-style GUI (live tweaks, export profiles)
      ];

      services.kanshi = {
        enable = true;
        settings = [
          # Writable scratchpad for transient monitors (see home.activation
          # below). nwg-displays exports here; known combos stay in this file.
          {include = "/home/vkarasen/.config/kanshi/runtime";}

          {
            profile = {
              name = "mobile";
              outputs = [
                {
                  criteria = "eDP-1";
                  status = "enable";
                  scale = 1.0;
                }
              ];
            };
          }

          {
            profile = {
              name = "docked";
              # Clamshell: the Thunderbolt LG is the only output (eDP off).
              # The criteria is make+model; verify the exact string next time
              # the monitor is docked via `hyprctl monitors` / `wlr-randr`.
              outputs = [
                {
                  criteria = "LG Electronics 38WN95C";
                  status = "enable";
                  position = "0,0";
                  scale = 1.0;
                }
                {
                  criteria = "eDP-1";
                  status = "disable";
                }
              ];
            };
          }
        ];
      };

      # Seed the writable runtime include as a real file (not a store symlink)
      # so nwg-displays / the user can append transient profiles to it.
      home.activation.kanshiRuntime = lib.hm.dag.entryAfter ["writeBoundary"] ''
        touch "$HOME/.config/kanshi/runtime"
      '';
    };
  };
}
