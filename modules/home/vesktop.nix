# Dendritic aspect: vesktop (home-manager class) — the Vesktop Discord
# client, whose bundled Vencord gives the theming/plugin layer upstream
# Discord lacks. Bundled by the desktop aspect (modules/home/desktop.nix)
# alongside Stylix, so importing desktop is what brings Vesktop to a host:
# desktop IS the GUI statement, so no `my.gui.enable` gate is needed here.
# The standalone TUI-only config (which never imports desktop) stays
# Vesktop-free. Selection is therefore per-GUI-host, not per-machine.
{...}: {
  flake.modules.homeManager.vesktop = {...}: {
    programs.vesktop.enable = true;
  };
}
