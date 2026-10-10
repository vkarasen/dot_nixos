# Dendritic aspect: neovide (home-manager class) — the Neovide GUI editor,
# wired as Tridactyl's `editorcmd` (see modules/home/tridactyl/default.nix) so `:editor`
# opens the current text field in a graphical Neovim.
#
# GUI-only: gated on `my.gui.enable`, so the standalone TUI-only config never
# pulls a GUI editor. Selection for this host happens in modules/hosts/troy.nix.
{...}: {
  flake.modules.homeManager.neovide = {
    config,
    lib,
    ...
  }: {
    programs.neovide.enable = lib.mkIf config.my.gui.enable true;
  };
}
