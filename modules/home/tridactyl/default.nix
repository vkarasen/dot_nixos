# Dendritic aspect: tridactyl (home-manager class) — Vim-like Firefox
# keybindings. Imports the standalone `programs.tridactyl` module (./_module.nix)
# and supplies this repo's starter config (settings + binds). Adds the Tridactyl
# extension to the vkarasen profile (declared in modules/home/browser.nix), the
# tridactyl-native messenger host that lets `:editor` hand a page's text field to
# the GUI editor, and a starter tridactylrc of Vim-style keybindings.
#
# GUI-only: the whole block is gated on `my.gui.enable`, which the desktop
# aspect sets true, so the standalone TUI-only config never pulls it.
# Selection for this host happens in modules/hosts/troy.nix.
{inputs, ...}: {
  flake.modules.homeManager.tridactyl = {
    pkgs,
    config,
    lib,
    ...
  }: let
    # Generated Tridactyl index: :set settings (from src/lib/config.ts,
    # namespaced `set.*`) plus ex commands (from src/excmds.ts, namespaced
    # `excmd.*`), built from the pinned tridactyl flake input by
    # _parse-config.cjs + _parse-excmds.cjs, merged into one index.json.
    tridactylIndex =
      pkgs.runCommand "tridactyl-index" {
        buildInputs = [pkgs.nodejs pkgs.jq];
        NODE_PATH = "${pkgs.typescript_5}/lib/node_modules";
      } ''
        mkdir -p $out
        node ${./_parse-config.cjs} ${inputs.tridactyl}/src/lib/config.ts > settings.json
        node ${./_parse-excmds.cjs} ${inputs.tridactyl}/src/excmds.ts > excmds.json
        jq -s 'add' settings.json excmds.json > $out/index.json
      '';
  in {
    imports = [./_module.nix];

    programs.tridactyl = {
      enable = true;
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

    # The generated Tridactyl index (`set.*` settings + `excmd.*` commands),
    # consumed by the television `tridactyl` channel
    # (modules/home/television/default.nix). Built from the pinned tridactyl
    # flake input at build time (tridactylIndex above).
    xdg.configFile."tridactyl/index.json" = lib.mkIf config.my.gui.enable {
      source = "${tridactylIndex}/index.json";
    };
  };
}
