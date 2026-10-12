# Library module: the `programs.ffpref` option set and its implementation —
# builds the generated Firefox-preference index, materializes it at
# xdg.configFile."ffprefs/index.json", and wires the television `ffpref`
# channel that consumes it. Imported by default.nix (the browser aspect);
# exposed for cross-flake import as flake.homeModules.ffpref-module. Keep this
# generic: no repo-specific settings here.
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.ffpref;

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
  # static default) else the StaticPrefList `value`. The index is consumed by
  # the television `ffpref` channel declared below.
  ffprefsIndex =
    pkgs.runCommand "ffprefs-index" {
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
  options.programs.ffpref = {
    enable = lib.mkEnableOption "the generated Firefox-preference index (and its television channel)";
  };

  config = lib.mkIf cfg.enable {
    # The generated Firefox-preference index (every pref name -> type /
    # default / description / source), built from the pinned Firefox at build
    # time (ffprefsIndex above) and materialized at ~/.config/ffprefs/index.json.
    xdg.configFile."ffprefs/index.json" = {
      source = "${ffprefsIndex}/index.json";
    };

    # Firefox-preference index: every pref name -> type / default /
    # description / source, from the index generated above. The source command
    # tolerates the index's absence (`|| true`) because television is always-on
    # while the index is only materialized when programs.ffpref.enable is set.
    programs.television.channels.ffpref = {
      metadata = {
        name = "ffpref";
        description = "Firefox prefs: type / default / description (generated index)";
      };
      source.command = ''
        test -f ~/.config/ffprefs/index.json && jq -r 'keys[]' ~/.config/ffprefs/index.json || true
      '';
      preview.command = ''jq -r --arg k '{}' '.[$k] as $o | $o.description, "", ("Type: " + $o.type) + "   Default: " + $o.default, ("Source: " + $o.source)' ~/.config/ffprefs/index.json | fold -s -w 80'';
    };
  };
}
