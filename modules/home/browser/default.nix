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
  }: let
    # Generated Firefox-preference index: every pref name from the pinned
    # `firefox-unwrapped`, merged into one flat JSON map by _parse-ffprefs.cjs.
    # Sources: StaticPrefList.yaml (from firefox-unwrapped.src — explicit C++
    # types + `#` doc-comment descriptions) plus the RESOLVED JS default-pref
    # files pulled out of the gre / browser omni.ja archives and the two
    # unpacked distro files (all #ifdefs already applied by the build). The
    # resolved JS files have their comments stripped, so two extra
    # DESCRIPTION-ONLY files (all.js + firefox.js from the same tarball) supply
    # the `//` blocks. `type`/`description` come from StaticPrefList when
    # present; `default` is the resolved JS value (which overrides the C++
    # static default) else the StaticPrefList `value`. Consumed by the
    # television `ffpref` channel (modules/home/television/default.nix) and
    # materialized at ~/.config/ffprefs/index.json.
    ffprefsIndex = pkgs.runCommand "ffprefs-index" {
      buildInputs = [pkgs.nodejs pkgs.unzip];
    } ''
      mkdir -p $out js
      # unzip exits non-zero on omni.ja's prepended header even though it writes
      # the member to stdout correctly, hence `|| true`.
      unzip -p ${pkgs.firefox-unwrapped}/lib/firefox/omni.ja greprefs.js > js/greprefs.js 2>/dev/null || true
      unzip -p ${pkgs.firefox-unwrapped}/lib/firefox/omni.ja defaults/pref/PdfJsDefaultPrefs.js > js/PdfJsDefaultPrefs.js 2>/dev/null || true
      unzip -p ${pkgs.firefox-unwrapped}/lib/firefox/browser/omni.ja defaults/preferences/firefox.js > js/firefox.js 2>/dev/null || true
      unzip -p ${pkgs.firefox-unwrapped}/lib/firefox/browser/omni.ja defaults/preferences/firefox-branding.js > js/firefox-branding.js 2>/dev/null || true
      unzip -p ${pkgs.firefox-unwrapped}/lib/firefox/browser/omni.ja defaults/preferences/debugger.js > js/debugger.js 2>/dev/null || true
      cp ${pkgs.firefox-unwrapped}/lib/firefox/defaults/pref/channel-prefs.js js/
      cp ${pkgs.firefox-unwrapped}/lib/firefox/browser/defaults/preferences/nixos-default-prefs.js js/
      # Fail loudly if a pref file came out empty — silent layout drift. The
      # exit-2 from unzip above is benign; an empty member is not.
      for f in js/*.js; do test -s "$f" || { echo "ERROR: empty pref file $f"; exit 1; }; done
      tar -xf ${pkgs.firefox-unwrapped.src} --wildcards -O '*/modules/libpref/init/StaticPrefList.yaml' > StaticPrefList.yaml
      tar -xf ${pkgs.firefox-unwrapped.src} --wildcards -O '*/modules/libpref/init/all.js' > desc-all.js
      tar -xf ${pkgs.firefox-unwrapped.src} --wildcards -O '*/browser/app/profile/firefox.js' > desc-firefox.js
      # Files are passed in LOAD order (GRE before app defaults) so the last
      # writer wins matches Firefox's effective default — greprefs.js must NOT
      # clobber firefox.js for the ~39 prefs both define.
      FFPREF_DESC_FILES="desc-all.js desc-firefox.js" node ${./_parse-ffprefs.cjs} \
        StaticPrefList.yaml js/greprefs.js js/PdfJsDefaultPrefs.js js/firefox.js js/firefox-branding.js js/debugger.js js/channel-prefs.js js/nixos-default-prefs.js \
        > $out/index.json
    '';
  in {
    programs.firefox = lib.mkIf config.my.gui.enable {
      enable = true;

      profiles."vkarasen" = {
        isDefault = true;

        extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
          ublock-origin # ad/sponsor blocking (full MV2)
          sponsorblock # YouTube sponsor-segment skipping
          darkreader # dark-by-default catch-all for sites that ignore prefers-color-scheme
          reddit-enhancement-suite
        ];

        settings = {
          # Auto-enable the declaratively-installed add-ons instead of asking
          # for a manual click on first launch.
          "extensions.autoDisableScopes" = 0;

          # Intel VA-API hardware video decode (YouTube etc.). The iHD driver
          # itself is installed system-side in modules/hosts/troy.nix.
          "media.rdd-ffmpeg.enabled" = true;

          # Force `prefers-color-scheme: dark` in web content (plain pref, not
          # extension storage) so sites that support it (e.g. YouTube) render
          # their own dark UI; Dark Reader above covers the rest.
          "layout.css.prefers-color-scheme.content-override" = 0;

          # Native tab discarding: let Firefox unload background tabs under
          # memory pressure, and only restore session tabs on demand, instead
          # of keeping full history/viewer state for every tab.
          "browser.tabs.unloadOnLowMemory" = true;
          "browser.sessionstore.restore_on_demand" = true;
          "browser.sessionhistory.max_total_viewers" = 2;

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

    # The generated Firefox-preference index (every pref name -> type /
    # default / description / source), consumed by the television `ffpref`
    # channel (modules/home/television/default.nix). Built from the pinned
    # Firefox at build time (ffprefsIndex above).
    xdg.configFile."ffprefs/index.json" = lib.mkIf config.programs.firefox.enable {
      source = "${ffprefsIndex}/index.json";
    };
  };
}
