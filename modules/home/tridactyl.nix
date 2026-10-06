# Dendritic aspect: tridactyl (home-manager class) — Vim-like Firefox
# keybindings. Adds the Tridactyl extension to the vkarasen profile (declared
# in modules/home/browser.nix), the tridactyl-native messenger host that lets
# `:editor` hand a page's text field to the GUI editor, and a starter
# .tridactylrc that mirrors this repo's nixvim leader (`;`) bindings.
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
  }: {
    # The native messenger host manifest is browser-global (not per-profile),
    # so it lives on programs.firefox.nativeMessagingHosts directly.
    programs.firefox.nativeMessagingHosts = lib.mkIf config.my.gui.enable [
      pkgs.tridactyl-native
    ];

    # The Tridactyl extension itself, attached to the vkarasen profile. The
    # .xpi comes from rycee's firefox-addons flake input (same source as the
    # other add-ons in modules/home/browser.nix).
    programs.firefox.profiles."vkarasen".extensions.packages = lib.mkIf config.my.gui.enable (
      with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
        tridactyl
      ]
    );

    xdg.configFile."tridactyl/tridactylrc" = lib.mkIf config.my.gui.enable {
      text = ''
        " Tridactyl starter - mirrors this repo's nixvim setup (leader `;`).

        " ---- Find (neovim uses stock / ? n N; Tridactyl leaves / unbound) ----
        bind / fillcmdline find
        bind n findnext
        bind N findprev

        " ---- Motion ----
        bind j scrollline 20
        bind k scrollline -20

        " neovim H/L move to adjacent window => adjacent tab here
        bind H tabprev
        bind L tabnext

        " history: backspace / shift+backspace
        bind <BS> back
        bind <S-BS> forward

        " ---- Edit-in-vim (needs native messenger + GUI editor) ----
        set editorcmd neovide
      '';
    };
  };
}
