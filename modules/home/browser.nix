# Dendritic aspect: browser (home-manager class) — Firefox, configured
# declaratively with pinned add-ons (uBlock Origin + SponsorBlock) and Intel
# VA-API video-decode prefs. Theming is owned by Stylix (modules/home/stylix.nix),
# not here.
#
# GUI-only: the whole block is gated on `my.gui.enable`, which the desktop
# aspect (modules/home/desktop.nix) sets true — importing desktop IS the GUI
# statement. So a browser is never a separate always-on concern; it follows
# the GUI, and the standalone TUI-only config (which omits desktop) never
# pulls it. Selection for this host happens in modules/hosts/troy.nix.
#
# The add-on packages come from rycee's firefox-addons flake input (declared
# in flake.nix): pinned .xpi derivations that expose `addonId` in passthru,
# the contract home-manager's `extensions.packages` reads.
{inputs, ...}: {
  flake.modules.homeManager.browser = {
    pkgs,
    config,
    lib,
    ...
  }: {
    programs.firefox = lib.mkIf config.my.gui.enable {
      enable = true;

      profiles."vkarasen" = {
        isDefault = true;

        extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin # ad/sponsor blocking (full MV2)
          sponsorblock # YouTube sponsor-segment skipping
          darkreader # dark-by-default catch-all for sites that ignore prefers-color-scheme
        ];

        settings = {
          # Auto-enable the declaratively-installed add-ons instead of asking
          # for a manual click on first launch.
          "extensions.autoDisableScopes" = 0;

          # Intel VA-API hardware video decode (YouTube etc.). The iHD driver
          # itself is installed system-side in modules/nixos/desktop.nix.
          "media.ffmpeg.vaapi.enabled" = true;
          "media.rdd-ffmpeg.enabled" = true;

          # Force `prefers-color-scheme: dark` in web content (plain pref, not
          # extension storage) so sites that support it (e.g. YouTube) render
          # their own dark UI; Dark Reader above covers the rest.
          "layout.css.prefers-color-scheme.content-override" = 0;

          # firefox-gnome-theme optional contrast prefs (plain prefs, read by
          # the theme CSS Stylix's firefoxGnomeTheme target already imports —
          # see modules/home/stylix.nix).
          "gnomeTheme.activeTabContrast" = true;
          # Deliberately false: on Hyprland (no client-side decorations) this
          # forces Firefox's own window-close button into the tab strip,
          # producing a stray floating "X" disconnected from any tab.
          "gnomeTheme.tabsAsHeaderbar" = false;
        };

        # firefox-gnome-theme + Stylix's base16 template leave chrome text at
        # GTK system colors (-moz-headerbartext / -moz-dialogtext / CaptionText,
        # dark on this box) instead of the theme's own light foreground, so
        # both tab labels and (Alt-revealed) menu-bar labels render
        # dark-on-dark. This snippet wires the theme's `--gnome-window-color`
        # to the actual text-color tokens Firefox reads, and adds a persistent
        # 1px border around every tab (the theme's own separator is
        # dark-on-dark too and skips selected/hover/first tabs). This merges
        # with (appends after) Stylix's own `userChrome` for this profile:
        # home-manager's `userChrome` option is `types.lines`, so multiple
        # module definitions concatenate rather than conflict.
        userChrome = lib.mkAfter ''
          :root {
            --toolbox-text-color: var(--gnome-window-color) !important;
            --toolbar-text-color: var(--gnome-window-color) !important;
            --tab-selected-textcolor: var(--gnome-window-color) !important;
            --gnome-tabbar-tab-separator-color: color-mix(in srgb, var(--gnome-window-color) 22%, transparent) !important;
          }
          #TabsToolbar,
          #toolbar-menubar,
          #nav-bar,
          #PersonalToolbar {
            color: var(--gnome-window-color) !important;
          }
          .tabbrowser-tab .tab-background {
            box-shadow: 0 0 0 1px var(--gnome-tabbar-tab-separator-color) !important;
          }

          /* Same class of bug on the doorhanger/arrowpanel permission prompts
             (geolocation, notifications, ...): the theme only sets
             `--panel-text-color`/`--arrowpanel-color` on `panel:not([remote])`
             (parts/popups.css), leaving every remote panel — including the
             notification doorhanger, which is `panel#notification-popup[remote="true"]`
             — on Firefox's Linux default `--panel-text-color: FieldText` (a raw
             GTK system color, dark on this box) over the theme's dark
             `--gnome-menu-background`. (Non-remote panels are fine: they pick up
             `--gnome-menu-color`, which resolves through `light.css`'s
             `var(--gnome-window-color)` to Stylix's light foreground regardless of
             dark mode.) Rebind the panel text token directly for both notification
             panels (the standalone doorhanger and its AppMenu mirror). */
          #notification-popup,
          #appMenu-notification-popup {
            --panel-text-color: var(--gnome-window-color) !important;
            --arrowpanel-color: var(--gnome-window-color) !important;
          }
        '';
      };
    };
  };
}
