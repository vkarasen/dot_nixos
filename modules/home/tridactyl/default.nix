# Dendritic aspect: tridactyl (home-manager class) — Vim-like Firefox
# keybindings. Imports the standalone `programs.tridactyl` module (./_module.nix)
# and supplies this repo's starter config (settings + binds). Adds the Tridactyl
# extension to the vkarasen profile (declared in
# modules/home/browser/default.nix), the
# tridactyl-native messenger host that lets `:editor` hand a page's text field to
# the GUI editor, and a starter tridactylrc of Vim-style keybindings.
#
# Browser-following: Tridactyl is a Firefox extension, so both blocks below are
# gated on `programs.firefox.enable` (set by the browser aspect,
# modules/home/browser/default.nix) rather than the separate `my.gui.enable`
# flag — a host with Firefox disabled does not pull the extension, the native
# messenger, or the generated index. Selection for this host happens in
# modules/hosts/troy.nix.
{inputs, ...}: {
  flake.modules.homeManager.tridactyl = {
    pkgs,
    config,
    lib,
    ...
  }: {
    imports = [./_module.nix ./_index-module.nix];

    # Build + materialize the generated Tridactyl index (and its television
    # channel) from the pinned tridactyl flake input — implementation lives in
    # ./_index-module.nix.
    programs.tridactyl-index = {
      enable = lib.mkIf config.programs.firefox.enable true;
      source = inputs.tridactyl;
    };

    programs.tridactyl = {
      enable = lib.mkIf config.programs.firefox.enable true;
      firefoxProfile = "vkarasen";
      extensionPackage = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.tridactyl;

      # Starter :set settings (translated from the old hand-written rc).
      settings = {
        editorcmd = "neovide";
        hintfiltermode = "vimperator-reflow";
        hinthideobscured = true;
        profiledir = "${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/${config.programs.firefox.profiles.${config.programs.tridactyl.firefoxProfile}.path}";
      };

      # Starter keybindings.
      binds = {
        "/" = "fillcmdline find";
        "n" = "findnext";
        "N" = "findprev";
        "j" = "scrollline 20";
        "J" = "scrollline 1";
        "k" = "scrollline -20";
        "K" = "scrollline -1";
        "h" = "tabprev";
        "l" = "tabnext";
        "<BS>" = "back";
        "<S-BS>" = "forward";
      };
    };
  };
}
